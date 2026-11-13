/**
 * Shiprocket courier integration (Bigfoot Retail Solutions).
 *
 * Flow: when an order's payment flips to SUCCESS, the `onOrderPaid`
 * trigger creates a Shiprocket shipment automatically:
 *
 *   1. Ensure a Shiprocket pickup location exists for the seller
 *      (nickname `TREGA-<sellerUid>`, created from the listing's
 *      private pickup address on first use).
 *   2. Create an adhoc order (Shiprocket `order_id` is the Trega order
 *      doc id, so webhook events map back exactly).
 *   3. Check courier serviceability and pick a courier: Blue Dart for
 *      high-value orders (Rs 10,000+) when available, otherwise the
 *      highest-rated courier with the earliest ETD. Falls back to
 *      Shiprocket's automatic selection when the check fails.
 *   4. Assign an AWB (this debits the Shiprocket wallet) and request
 *      pickup from the seller's address.
 *
 * Tracking updates arrive on the `courierTracking` webhook (panel
 * configured, `x-api-key` token auth, no HMAC) and move the order
 * forward through pickup_scheduled, picked_up, in_transit, delivered.
 * The webhook URL must not contain `shiprocket`, `kartrocket`, `sr`
 * or `kr`, which is why the function is named `courierTracking`.
 *
 * Secrets (set on the deploy machine, never in chat or code):
 *   firebase functions:secrets:set SHIPROCKET_API_EMAIL
 *   firebase functions:secrets:set SHIPROCKET_API_PASSWORD
 *   firebase functions:secrets:set SHIPROCKET_WEBHOOK_KEY
 * The API user is created in the Shiprocket panel (Settings, API, Add
 * New API User) with a distinct email and Buyer Details Access ALLOWED,
 * or PII comes back suppressed. There is NO sandbox: every call is
 * live against the real wallet, and AWB assignment debits it.
 *
 * Failure handling: shipment creation never breaks payment. Any step
 * failing leaves `shipmentStatus: "failed"` plus `shipmentError` on
 * the order doc, the admin retries with the `retryShipment` callable,
 * and the manual fulfillment flow still works. Creation is resumable:
 * stored Shiprocket ids let a retry skip completed steps, and the
 * Shiprocket order_id is unique per account so a duplicate create is
 * rejected rather than double-booked.
 *
 * Weight/dimensions: listings carry no weight, so category defaults
 * apply (see FREIGHT_DEFAULTS). Wrong weights cause Shiprocket weight
 * discrepancy charges; capturing real weights in the sell flow is a
 * later improvement, not a launch blocker.
 */
import * as admin from "firebase-admin";
import { timingSafeEqual } from "crypto";
import { HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import {
  SHIPROCKET_API_EMAIL,
  SHIPROCKET_API_PASSWORD,
  SHIPROCKET_WEBHOOK_KEY,
  SHIPROCKET_BASE,
} from "./config";
import { queueNotification, NotificationType } from "./marketplace";

type AddressMap = {
  name?: string;
  phone?: string;
  line1?: string;
  line2?: string;
  city?: string;
  state?: string;
  pincode?: string;
};

/** Steps of the creation state machine, stored as `shipmentStep`. */
type ShipmentStep =
  | "pickup_location"
  | "create_order"
  | "assign_awb"
  | "request_pickup"
  | "done";

class ShiprocketError extends Error {
  status: number;
  constructor(message: string, status = 0) {
    super(message);
    this.status = status;
  }
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

// ------------------------------------------------------------------ auth ---

/** API credentials from secrets, or null when Shiprocket is not set up. */
function credentials(): { email: string; password: string } | null {
  try {
    const email = SHIPROCKET_API_EMAIL.value();
    const password = SHIPROCKET_API_PASSWORD.value();
    if (!email || !password) return null;
    return { email, password };
  } catch {
    return null;
  }
}

// Shiprocket JWTs live 10 days; refresh a day early. In-memory cache is
// enough: a cold instance just logs in again, and the password (not the
// token) is what is stored, so there is always a way back.
let tokenCache: { token: string; expiresAt: number } | null = null;

async function login(
  creds: { email: string; password: string }
): Promise<string> {
  const res = await fetch(`${SHIPROCKET_BASE}/auth/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email: creds.email, password: creds.password }),
    signal: AbortSignal.timeout(15000),
  });
  const json = (await parseJson(res)) as Record<string, unknown>;
  const token = json.token;
  if (res.status !== 200 || typeof token !== "string" || !token) {
    throw new ShiprocketError(
      `Shiprocket login failed: ${shiprocketMessage(json, res.status)}`,
      res.status
    );
  }
  tokenCache = { token, expiresAt: Date.now() + 9 * 86400_000 };
  return token;
}

async function getToken(): Promise<string> {
  const creds = credentials();
  if (!creds) {
    throw new ShiprocketError(
      "Shiprocket is not configured (SHIPROCKET_API_EMAIL / SHIPROCKET_API_PASSWORD secrets missing)"
    );
  }
  if (tokenCache && Date.now() < tokenCache.expiresAt) {
    return tokenCache.token;
  }
  return login(creds);
}

// -------------------------------------------------------------- requests ---

async function parseJson(res: Response): Promise<unknown> {
  const text = await res.text();
  if (!text) return {};
  try {
    return JSON.parse(text) as unknown;
  } catch {
    return {};
  }
}

/** Shiprocket error envelopes vary; pull a readable message out of any. */
function shiprocketMessage(json: unknown, status: number): string {
  const body = (json ?? {}) as Record<string, unknown>;
  if (typeof body.message === "string" && body.message) {
    const errors = body.errors as Record<string, unknown> | undefined;
    if (errors && typeof errors === "object") {
      const first = Object.values(errors)[0];
      const detail = Array.isArray(first) ? String(first[0] ?? "") : "";
      return detail ? `${body.message}: ${detail}` : body.message;
    }
    return body.message;
  }
  return `Shiprocket request failed (HTTP ${status})`;
}

/**
 * One Shiprocket API call with auth retry (re-login once on 401) and
 * exponential backoff on 429 / 5xx. Shiprocket publishes no rate
 * limits, so writes stay serial and back off when told to.
 */
async function srRequest<T>(
  path: string,
  init: { method?: string; body?: unknown },
  attempt = 0
): Promise<T> {
  const token = await getToken();
  const res = await fetch(`${SHIPROCKET_BASE}${path}`, {
    method: init.method ?? "GET",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: init.body === undefined ? undefined : JSON.stringify(init.body),
    signal: AbortSignal.timeout(15000),
  });
  if (res.status === 401 && attempt === 0) {
    tokenCache = null;
    return srRequest<T>(path, init, 1);
  }
  const json = await parseJson(res);
  if (res.status === 429 || (res.status >= 500 && res.status <= 504)) {
    if (attempt < 2) {
      await sleep(600 * (attempt + 1));
      return srRequest<T>(path, init, attempt + 1);
    }
  }
  if (!res.ok) {
    throw new ShiprocketError(shiprocketMessage(json, res.status), res.status);
  }
  return json as T;
}

// -------------------------------------------------------- pickup points ---

let pickupCache: { at: number; names: Set<string> } | null = null;
const PICKUP_CACHE_TTL_MS = 10 * 60_000;

async function listPickupNames(): Promise<Set<string>> {
  if (pickupCache && Date.now() - pickupCache.at < PICKUP_CACHE_TTL_MS) {
    return pickupCache.names;
  }
  const json = (await srRequest("/settings/company/pickup", {})) as Record<
    string,
    unknown
  >;
  const data = json.data as Record<string, unknown> | unknown[] | undefined;
  const rows: unknown[] = Array.isArray(data)
    ? data
    : Array.isArray((data as Record<string, unknown>)?.shipping_address)
      ? ((data as Record<string, unknown>).shipping_address as unknown[])
      : [];
  const names = new Set<string>();
  for (const row of rows) {
    const name = (row as Record<string, unknown>)?.pickup_location;
    if (typeof name === "string" && name) names.add(name);
  }
  pickupCache = { at: Date.now(), names };
  return names;
}

/**
 * The pickup location nickname for a seller, creating it on first use.
 * The nickname is the seller uid, so it is stable and unique per
 * account; the human name, phone and address travel in the fields.
 */
async function ensurePickupLocation(
  sellerUid: string,
  sellerName: string,
  sellerPhone: string,
  sellerEmail: string | undefined,
  addr: AddressMap
): Promise<string> {
  const nickname = `TREGA-${sellerUid}`;
  const names = await listPickupNames();
  if (names.has(nickname)) return nickname;
  await srRequest("/settings/company/addpickup", {
    method: "POST",
    body: {
      pickup_location: nickname,
      name: sellerName,
      email: sellerEmail ?? "contact@trega.in",
      phone: sellerPhone,
      address: addr.line1,
      address_2: addr.line2 ?? "",
      city: addr.city,
      state: addr.state,
      country: "India",
      pin_code: addr.pincode,
    },
  });
  pickupCache?.names.add(nickname);
  return nickname;
}

// ------------------------------------------------------------- helpers ---

/** E.164 / formatted phone numbers down to the 10 digits Shiprocket wants. */
function toTenDigit(phone: unknown): string {
  const digits = String(phone ?? "").replace(/\D/g, "");
  return digits.length > 10 ? digits.slice(-10) : digits;
}

function asAddressMap(v: unknown): AddressMap | null {
  if (!v || typeof v !== "object") return null;
  const m = v as Record<string, unknown>;
  const s = (k: string) =>
    typeof m[k] === "string" ? (m[k] as string).trim() : "";
  const addr: AddressMap = {
    name: s("name"),
    phone: s("phone"),
    line1: s("line1"),
    line2: s("line2"),
    city: s("city"),
    state: s("state"),
    pincode: s("pincode"),
  };
  if (!addr.line1 || !addr.city || !addr.state || !addr.pincode) return null;
  return addr;
}

function splitName(full: string): { first: string; last: string } {
  const parts = full.trim().split(/\s+/).filter(Boolean);
  return { first: parts[0] ?? "", last: parts.slice(1).join(" ") };
}

/** `YYYY-MM-DD HH:mm` in IST, the format Shiprocket order creation wants. */
function shiprocketOrderDate(d: Date): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Kolkata",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).formatToParts(d);
  const get = (t: Intl.DateTimeFormatPartTypes) =>
    parts.find((p) => p.type === t)?.value ?? "";
  return `${get("year")}-${get("month")}-${get("day")} ${get("hour")}:${get("minute")}`;
}

/**
 * Default parcel weight (kg) and box dimensions (cm) per category.
 * Listings carry no weight, so these stand in until the sell flow
 * captures real weights. Charge weight minimum is 0.5 kg.
 */
const FREIGHT_DEFAULTS: Record<
  string,
  { weight: number; length: number; breadth: number; height: number }
> = {
  mobiles: { weight: 0.5, length: 20, breadth: 12, height: 8 },
  laptops: { weight: 2.5, length: 45, breadth: 32, height: 8 },
  cameras: { weight: 1.5, length: 30, breadth: 22, height: 15 },
  gaming: { weight: 2, length: 35, breadth: 28, height: 12 },
  music: { weight: 3, length: 40, breadth: 30, height: 15 },
  fashion: { weight: 0.5, length: 30, breadth: 22, height: 5 },
  furniture: { weight: 10, length: 60, breadth: 50, height: 40 },
  homeappliances: { weight: 8, length: 55, breadth: 45, height: 40 },
  cycles: { weight: 12, length: 120, breadth: 25, height: 70 },
  watches: { weight: 0.5, length: 18, breadth: 12, height: 8 },
  collectibles: { weight: 1, length: 30, breadth: 22, height: 12 },
  books: { weight: 1, length: 30, breadth: 22, height: 8 },
  others: { weight: 1, length: 30, breadth: 22, height: 12 },
};

function freightFor(categoryId: unknown): {
  weight: number;
  length: number;
  breadth: number;
  height: number;
} {
  const key = String(categoryId ?? "")
    .toLowerCase()
    .replace(/[^a-z0-9]/g, "");
  return FREIGHT_DEFAULTS[key] ?? FREIGHT_DEFAULTS.others;
}

// ------------------------------------------------------ courier choice ---

/**
 * Pick a courier from the serviceability response. High-value orders
 * (Rs 10,000+) prefer Blue Dart when it serves the route; otherwise the
 * highest-rated courier with the earliest ETD wins. Returns nulls to
 * let Shiprocket choose automatically when the check fails or finds
 * nothing usable, so a serviceability hiccup never blocks shipping.
 */
async function chooseCourier(
  pickupPincode: string,
  deliveryPincode: string,
  weight: number,
  amount: number
): Promise<{ courierId: number | null; etd: string | null }> {
  try {
    const q = new URLSearchParams({
      pickup_postcode: pickupPincode,
      delivery_postcode: deliveryPincode,
      cod: "0",
      weight: String(weight),
    });
    const json = (await srRequest(`/courier/serviceability/?${q}`, {})) as Record<
      string,
      unknown
    >;
    const data = json.data as Record<string, unknown> | undefined;
    const list = (data?.available_courier_companies ?? []) as unknown[];
    const usable = list.filter((c) => {
      const row = c as Record<string, unknown>;
      return row && !row.blocked && !row.odablock;
    }) as Record<string, unknown>[];
    if (usable.length === 0) return { courierId: null, etd: null };
    if (amount >= 10000) {
      const premium = usable
        .filter((c) => /blue\s*dart/i.test(String(c.courier_name ?? "")))
        .sort(
          (a, b) =>
            Number(a.etd_hours ?? 1e9) - Number(b.etd_hours ?? 1e9)
        );
      if (premium[0]) {
        return {
          courierId: Number(premium[0].courier_company_id),
          etd: String(premium[0].etd ?? "") || null,
        };
      }
    }
    const sorted = [...usable].sort(
      (a, b) =>
        Number(b.rating ?? 0) - Number(a.rating ?? 0) ||
        Number(a.etd_hours ?? 1e9) - Number(b.etd_hours ?? 1e9)
    );
    const pick = sorted[0];
    return {
      courierId: Number(pick.courier_company_id),
      etd: String(pick.etd ?? "") || null,
    };
  } catch (e) {
    logger.warn("Shiprocket serviceability check failed, auto-selecting courier", {
      error: e instanceof Error ? e.message : String(e),
    });
    return { courierId: null, etd: null };
  }
}

// ------------------------------------------------------- shipment steps ---

/**
 * Runs the creation steps for one paid order, resuming from whatever
 * the order doc already stores (Shiprocket ids, AWB). The caller owns
 * the `creating` claim; this function only moves forward and throws
 * ShiprocketError on the first failing step.
 */
async function runShipmentSteps(orderId: string): Promise<void> {
  const db = admin.firestore();
  const orderRef = db.collection("orders").doc(orderId);
  const snap = await orderRef.get();
  if (!snap.exists) throw new ShiprocketError("Order not found.");
  const order = snap.data() as Record<string, unknown>;
  const listingId = String(order.listingId ?? "");
  const buyerId = String(order.buyerId ?? "");
  const sellerId = String(order.sellerId ?? "");
  const amount = Number(order.amount ?? 0);

  const [listingSnap, detailsSnap, sellerSnap, buyerSnap] = await Promise.all([
    listingId ? db.collection("listings").doc(listingId).get() : null,
    listingId
      ? db.collection("listings").doc(listingId).collection("private").doc("details").get()
      : null,
    sellerId ? db.collection("users").doc(sellerId).get() : null,
    buyerId ? db.collection("users").doc(buyerId).get() : null,
  ]);
  const listing = listingSnap?.data() as Record<string, unknown> | undefined;
  const pickup = asAddressMap(detailsSnap?.data()?.pickupAddress);
  if (!pickup) {
    throw new ShiprocketError(
      "Seller pickup address is missing or unstructured; the seller must re-save it in Settings."
    );
  }
  const seller = sellerSnap?.data() as Record<string, unknown> | undefined;
  const sellerName = String(seller?.name ?? "").trim() || "Trega seller";
  const sellerPhone = toTenDigit(seller?.phone);
  if (sellerPhone.length !== 10) {
    throw new ShiprocketError("Seller phone number is missing or invalid.");
  }
  const sellerEmail =
    typeof seller?.email === "string" && seller.email ? seller.email : undefined;
  const buyerAddr = asAddressMap(order.deliveryAddress);
  if (!buyerAddr || !buyerAddr.name) {
    throw new ShiprocketError("Buyer delivery address is missing.");
  }
  const buyerPhone = toTenDigit(buyerAddr.phone);
  if (buyerPhone.length !== 10) {
    throw new ShiprocketError("Buyer phone number is missing or invalid.");
  }
  const buyer = buyerSnap?.data() as Record<string, unknown> | undefined;
  const buyerEmail =
    typeof buyer?.email === "string" && buyer.email ? buyer.email : undefined;
  const freight = freightFor(listing?.categoryId);
  const title = String(
    listing?.title ?? order.listingTitle ?? "Trega order"
  ).slice(0, 100);

  const setStep = async (step: ShipmentStep) =>
    orderRef.update({ shipmentStep: step });

  // Step 1: pickup location (idempotent by nickname lookup).
  await setStep("pickup_location");
  const pickupLocation = await ensurePickupLocation(
    sellerId,
    sellerName,
    sellerPhone,
    sellerEmail,
    pickup
  );

  // Step 2: Shiprocket order (skip when a previous attempt stored one).
  let srShipmentId = Number(order.srShipmentId ?? 0) || undefined;
  let srOrderId = Number(order.srOrderId ?? 0) || undefined;
  if (!srShipmentId) {
    await setStep("create_order");
    const buyerName = splitName(buyerAddr.name);
    const created = (await srRequest("/orders/create/adhoc", {
      method: "POST",
      body: {
        order_id: orderId,
        order_date: shiprocketOrderDate(new Date()),
        pickup_location: pickupLocation,
        channel_id: "",
        billing_customer_name: buyerName.first,
        billing_last_name: buyerName.last,
        billing_address: buyerAddr.line1,
        billing_address_2: buyerAddr.line2 ?? "",
        billing_city: buyerAddr.city,
        billing_pincode: buyerAddr.pincode,
        billing_state: buyerAddr.state,
        billing_country: "India",
        ...(buyerEmail ? { billing_email: buyerEmail } : {}),
        billing_phone: buyerPhone,
        shipping_is_billing: true,
        order_items: [
          {
            name: title,
            sku: listingId,
            units: 1,
            selling_price: String(amount),
            discount: "",
            tax: "",
            hsn: "",
          },
        ],
        payment_method: "Prepaid",
        sub_total: amount,
        total_discount: 0,
        length: freight.length,
        breadth: freight.breadth,
        height: freight.height,
        weight: freight.weight,
        order_type: "",
      },
    })) as Record<string, unknown>;
    srOrderId = Number(created.order_id ?? 0) || undefined;
    srShipmentId = Number(created.shipment_id ?? 0) || undefined;
    if (!srShipmentId) {
      throw new ShiprocketError(
        "Shiprocket order creation returned no shipment id."
      );
    }
    await orderRef.update({ srOrderId, srShipmentId, shipmentStep: "assign_awb" });
  }

  // Step 3: AWB assignment (this debits the wallet; skip if stored).
  let awbCode = typeof order.awbCode === "string" ? order.awbCode : undefined;
  let courierName =
    typeof order.courierName === "string" ? order.courierName : undefined;
  let etd = typeof order.etd === "string" ? order.etd : undefined;
  if (!awbCode) {
    const choice = await chooseCourier(
      pickup.pincode as string,
      buyerAddr.pincode as string,
      freight.weight,
      amount
    );
    const assigned = (await srRequest("/courier/assign/awb", {
      method: "POST",
      body: choice.courierId
        ? { shipment_id: srShipmentId, courier_id: choice.courierId }
        : { shipment_id: srShipmentId },
    })) as Record<string, unknown>;
    if (assigned.awb_assign_status !== 1) {
      throw new ShiprocketError(
        `Shiprocket AWB assignment failed: ${shiprocketMessage(assigned, 200)}`
      );
    }
    const data = (assigned.response as Record<string, unknown> | undefined)
      ?.data as Record<string, unknown> | undefined;
    awbCode = String(data?.awb_code ?? "");
    courierName = String(data?.courier_name ?? "");
    if (!awbCode) {
      throw new ShiprocketError("Shiprocket AWB assignment returned no AWB code.");
    }
    if (choice.etd) etd = choice.etd;
    await orderRef.update({
      awbCode,
      courierName,
      ...(etd ? { etd } : {}),
      shipmentStep: "request_pickup",
    });
  }

  // Step 4: request pickup from the seller's address.
  await setStep("request_pickup");
  const picked = (await srRequest("/courier/generate/pickup", {
    method: "POST",
    body: { shipment_id: [srShipmentId] },
  })) as Record<string, unknown>;
  if (picked.pickup_status !== 1) {
    throw new ShiprocketError(
      `Shiprocket pickup request failed: ${shiprocketMessage(picked, 200)}`
    );
  }
  const response = picked.response as Record<string, unknown> | undefined;
  const pickupDate = String(response?.pickup_scheduled_date ?? "");

  // Commit: shipment fields, fulfillment status (only when the order is
  // still `placed`, never overwrite a manual admin move), and a pickup
  // notification for both parties. The FCM push goes out via the
  // onNotificationCreate trigger, never awaited here.
  const fresh = await orderRef.get();
  const currentStatus = String(
    (fresh.data() as Record<string, unknown> | undefined)?.status ?? "placed"
  );
  const update: Record<string, unknown> = {
    shipmentStatus: "pickup_scheduled",
    shipmentStep: "done",
    shipmentError: admin.firestore.FieldValue.delete(),
    ...(pickupDate ? { pickupScheduledDate: pickupDate } : {}),
    trackingNote: `Pickup scheduled with ${courierName}, AWB ${awbCode}`,
  };
  if (currentStatus === "placed") update.status = "pickup_scheduled";
  const batch = db.batch();
  batch.update(orderRef, update);
  queueNotification(batch, buyerId, {
    type: NotificationType.shipmentUpdate,
    title: "Pickup scheduled",
    body: `Your order is being picked up. AWB ${awbCode}.`,
    data: { orderId },
  });
  queueNotification(batch, sellerId, {
    type: NotificationType.shipmentUpdate,
    title: "Courier pickup scheduled",
    body: `Keep "${title}" packed and ready. AWB ${awbCode}.`,
    data: { orderId },
  });
  await batch.commit();
  logger.info("Shiprocket shipment created", {
    orderId,
    awbCode,
    courierName,
  });
}

/**
 * Claims and creates a shipment for one order. Returns a reason instead
 * of throwing for the expected no-op cases (not paid, already handled,
 * Shiprocket not configured); unexpected failures land on the order doc
 * as `shipmentStatus: "failed"` for the admin to retry.
 */
export async function createShipmentForOrder(
  orderId: string
): Promise<{ created: boolean; reason?: string }> {
  const db = admin.firestore();
  const orderRef = db.collection("orders").doc(orderId);
  const claim = await db.runTransaction(async (tx) => {
    const snap = await tx.get(orderRef);
    if (!snap.exists) return "missing";
    const d = snap.data() as Record<string, unknown>;
    if (d.paymentStatus !== "SUCCESS") return "not_paid";
    const st = d.shipmentStatus as string | undefined;
    if (st === "creating" || st === "pickup_scheduled") return "already";
    if (st === "failed") return "failed_awaiting_retry";
    if (!credentials()) return "not_configured";
    tx.update(orderRef, {
      shipmentStatus: "creating",
      shipmentStep: "pickup_location",
      shipmentError: admin.firestore.FieldValue.delete(),
    });
    return "claimed";
  });
  if (claim !== "claimed") {
    logger.info("Shiprocket shipment skipped", { orderId, reason: claim });
    return { created: false, reason: claim };
  }
  try {
    await runShipmentSteps(orderId);
    return { created: true };
  } catch (e) {
    const message = e instanceof Error ? e.message : "Unknown shipment error";
    logger.error("Shiprocket shipment failed", { orderId, message });
    await orderRef.update({
      shipmentStatus: "failed",
      shipmentError: message.slice(0, 500),
    });
    return { created: false, reason: message };
  }
}

/** Trigger entry: fires on every order update, acts only on the payment flip. */
export async function onOrderPaidHandler(
  orderId: string,
  before: Record<string, unknown> | undefined,
  after: Record<string, unknown> | undefined
): Promise<void> {
  if (!after) return;
  if (before?.paymentStatus === "SUCCESS") return;
  if (after.paymentStatus !== "SUCCESS") return;
  if (after.shipmentStatus) return;
  try {
    await createShipmentForOrder(orderId);
  } catch (e) {
    logger.error("Shiprocket onOrderPaid failed", {
      orderId,
      error: e instanceof Error ? e.message : String(e),
    });
  }
}

/** Admin retry for a failed shipment. Resumes from the stored step. */
export async function retryShipmentHandler(
  isAdmin: boolean,
  orderId: unknown
): Promise<{ ok: boolean }> {
  if (!isAdmin) {
    throw new HttpsError("permission-denied", "Admin only.");
  }
  if (typeof orderId !== "string" || !orderId) {
    throw new HttpsError("invalid-argument", "orderId is required.");
  }
  const db = admin.firestore();
  const ref = db.collection("orders").doc(orderId);
  const claim = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return "missing";
    const d = snap.data() as Record<string, unknown>;
    if (d.paymentStatus !== "SUCCESS") return "not_paid";
    if (d.shipmentStatus !== "failed") return "not_failed";
    if (!credentials()) return "not_configured";
    tx.update(ref, {
      shipmentStatus: "creating",
      shipmentError: admin.firestore.FieldValue.delete(),
    });
    return "claimed";
  });
  if (claim === "missing") throw new HttpsError("not-found", "Order not found.");
  if (claim === "not_paid") {
    throw new HttpsError("failed-precondition", "Order is not paid.");
  }
  if (claim === "not_failed") {
    throw new HttpsError(
      "failed-precondition",
      "Shipment is not in a failed state."
    );
  }
  if (claim === "not_configured") {
    throw new HttpsError(
      "failed-precondition",
      "Shiprocket is not configured (secrets missing)."
    );
  }
  try {
    await runShipmentSteps(orderId);
    return { ok: true };
  } catch (e) {
    const message = e instanceof Error ? e.message : "Unknown shipment error";
    await ref.update({
      shipmentStatus: "failed",
      shipmentError: message.slice(0, 500),
    });
    throw new HttpsError("internal", `Shipment retry failed: ${message}`);
  }
}

// ------------------------------------------------------------- webhook ---

/** Forward-only rank for order statuses; terminal states rank highest. */
const STATUS_RANK: Record<string, number> = {
  placed: 0,
  pickup_scheduled: 1,
  picked_up: 2,
  in_transit: 3,
  delivered: 4,
  cancelled: 99,
  returned: 99,
};

/** Shiprocket order status_code to Trega order status. */
const SR_STATUS_MAP: Record<number, string> = {
  4: "pickup_scheduled",
  12: "pickup_scheduled",
  13: "pickup_scheduled",
  6: "picked_up",
  20: "in_transit",
  19: "in_transit",
  7: "delivered",
  5: "cancelled",
  9: "returned",
  15: "returned",
  16: "returned",
  17: "returned",
};

function notificationDoc(
  type: string,
  title: string,
  body: string,
  orderId: string
): Record<string, unknown> {
  return {
    type,
    title,
    body,
    data: { orderId },
    read: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

/**
 * Shiprocket tracking webhook. Auth is the panel-configured security
 * token in the `x-api-key` header compared in constant time; there is
 * no HMAC signature. Returns 200 for every validly authenticated call
 * (Shiprocket wants only 200s), including unknown orders.
 */
export async function handleShiprocketWebhook(
  apiKeyHeader: string | string[] | undefined,
  body: unknown
): Promise<{ ok: boolean; status: number }> {
  let expected = "";
  try {
    expected = SHIPROCKET_WEBHOOK_KEY.value();
  } catch {
    expected = "";
  }
  const provided = Array.isArray(apiKeyHeader) ? apiKeyHeader[0] : apiKeyHeader;
  if (
    !expected ||
    !provided ||
    provided.length !== expected.length ||
    !timingSafeEqual(Buffer.from(provided), Buffer.from(expected))
  ) {
    return { ok: false, status: 401 };
  }
  const payload = (body ?? {}) as Record<string, unknown>;
  const awb = String(payload.awb ?? "");
  const orderId = String(payload.order_id ?? "");
  const db = admin.firestore();
  let ref: admin.firestore.DocumentReference | null = null;
  if (orderId) {
    const snap = await db.collection("orders").doc(orderId).get();
    if (snap.exists) ref = snap.ref;
  }
  if (!ref && awb) {
    const q = await db
      .collection("orders")
      .where("awbCode", "==", awb)
      .limit(1)
      .get();
    if (!q.empty) ref = q.docs[0].ref;
  }
  if (!ref) {
    logger.warn("Shiprocket webhook for unknown order", { orderId, awb });
    return { ok: true, status: 200 };
  }
  const orderRef = ref;
  const statusId = Number(payload.current_status_id ?? 0);
  const mapped = SR_STATUS_MAP[statusId];
  const scans = Array.isArray(payload.scans) ? payload.scans : [];
  const latest = scans[scans.length - 1] as Record<string, unknown> | undefined;
  const note = latest
    ? `${String(latest.activity ?? "")}${latest.location ? `, ${String(latest.location)}` : ""}`.trim()
    : String(payload.current_status ?? "");
  const etd = String(payload.etd ?? "");
  const courierName = String(payload.courier_name ?? "");

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(orderRef);
    if (!snap.exists) return;
    const d = snap.data() as Record<string, unknown>;
    const current = String(d.status ?? "placed");
    const update: Record<string, unknown> = {};
    if (note) update.trackingNote = note.slice(0, 500);
    if (etd) update.etd = etd;
    if (courierName && !d.courierName) update.courierName = courierName;
    if (statusId === 14) {
      update.shipmentError =
        "Pickup error reported by the courier, check the Shiprocket panel.";
    }
    if (mapped && mapped !== current) {
      const terminal =
        current === "delivered" ||
        current === "cancelled" ||
        current === "returned";
      const curRank = STATUS_RANK[current] ?? 0;
      const newRank = STATUS_RANK[mapped] ?? 0;
      if (!terminal && (newRank > curRank || newRank === 99)) {
        update.status = mapped;
      }
    }
    if (Object.keys(update).length > 0) tx.update(orderRef, update);
    if (update.status === "delivered") {
      tx.set(
        db
          .collection("users")
          .doc(String(d.buyerId))
          .collection("notifications")
          .doc(),
        notificationDoc(
          NotificationType.shipmentUpdate,
          "Order delivered",
          "Your order has been delivered.",
          orderRef.id
        )
      );
    }
    if (update.status === "returned") {
      for (const uid of [String(d.buyerId), String(d.sellerId)]) {
        tx.set(
          db.collection("users").doc(uid).collection("notifications").doc(),
          notificationDoc(
            NotificationType.shipmentUpdate,
            "Order returned",
            "The shipment is on its way back to the seller.",
            orderRef.id
          )
        );
      }
    }
  });
  return { ok: true, status: 200 };
}
