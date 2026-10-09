import type { ReactNode } from 'react';
import { useAppConfig } from '../lib/firestore';
import StatusBadge from '../components/StatusBadge';
import { formatINR } from '../utils/format';

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="rounded-xl border border-stone-200 bg-white p-5 shadow-sm">
      <h2 className="mb-3 text-base font-bold text-stone-900">{title}</h2>
      {children}
    </section>
  );
}

function Row({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="flex items-center justify-between gap-4 border-b border-stone-100 py-2.5 last:border-0">
      <span className="text-sm text-stone-500">{label}</span>
      <span className="text-sm font-medium text-stone-900">{children}</span>
    </div>
  );
}

/** Read-only view of config/fees and config/delivery. Writes are console-only
 *  (firestore.rules sets `allow write: if false` on config/*). */
export default function Settings() {
  const { fees, delivery, loading, error } = useAppConfig();

  return (
    <div className="space-y-5">
      <div>
        <h1 className="text-2xl font-bold text-stone-900">Settings</h1>
        <p className="text-sm text-stone-500">App configuration, read live from Firestore.</p>
      </div>

      <div className="rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-800">
        Edited via Firebase console — the admin panel cannot write config (firestore.rules).
      </div>

      {error && (
        <div className="rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-700">{error}</div>
      )}

      {loading ? (
        <p className="py-10 text-center text-stone-500">Loading…</p>
      ) : (
        <>
          <Section title="Marketplace pricing">
            {fees ? (
              <div className="space-y-3">
                <p className="rounded-lg bg-trega-50 px-4 py-3 text-sm font-medium text-trega-800">
                  {fees.promoActive
                    ? `Zero Fee Launch is ACTIVE — only the ${formatINR(fees.deliveryFlat)} delivery fee applies`
                    : `Standard pricing: ${fees.sellerPct}% seller + ${fees.buyerPct}% buyer`}
                </p>
                <div>
                  <Row label="Launch promo">
                    {fees.promoActive ? (
                      <StatusBadge value="active" />
                    ) : (
                      <StatusBadge value="inactive" />
                    )}
                  </Row>
                  <Row label="Seller fee">{fees.sellerPct}%</Row>
                  <Row label="Buyer fee">{fees.buyerPct}%</Row>
                  <Row label="Delivery fee">{formatINR(fees.deliveryFlat)}</Row>
                  <Row label="GST on fees">{fees.gstPct}%</Row>
                </div>
              </div>
            ) : (
              <p className="text-sm text-stone-500">Not set — the app uses bundled defaults.</p>
            )}
          </Section>

          <Section title="Trega Express">
            {delivery ? (
              <div className="space-y-3">
                <div>
                  <Row label="Status">
                    {delivery.enabled ? (
                      <StatusBadge value="active" />
                    ) : (
                      <StatusBadge value="inactive" />
                    )}
                  </Row>
                  <Row label="Order cutoff">{delivery.cutoffHour}:00 local</Row>
                </div>
                <div>
                  <div className="mb-2 text-sm text-stone-500">Express cities</div>
                  {delivery.expressCities.length > 0 ? (
                    <div className="flex flex-wrap gap-2">
                      {delivery.expressCities.map((city) => (
                        <span
                          key={city}
                          className="rounded-full bg-trega-100 px-3 py-1 text-xs font-medium text-trega-700 ring-1 ring-inset ring-trega-200"
                        >
                          {city}
                        </span>
                      ))}
                    </div>
                  ) : (
                    <p className="text-sm text-stone-500">No cities configured.</p>
                  )}
                </div>
              </div>
            ) : (
              <p className="text-sm text-stone-500">Not set — the app uses bundled defaults.</p>
            )}
          </Section>
        </>
      )}
    </div>
  );
}
