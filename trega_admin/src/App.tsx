import { BrowserRouter, Navigate, Outlet, Route, Routes } from 'react-router-dom';
import { AuthProvider, useAuth } from './auth/AuthContext';
import Layout from './components/Layout';
import Login from './pages/Login';
import Dashboard from './pages/Dashboard';
import ReviewQueue from './pages/ReviewQueue';
import ListingDetail from './pages/ListingDetail';
import Listings from './pages/Listings';
import Users from './pages/Users';
import Orders from './pages/Orders';
import Bids from './pages/Bids';
import Categories from './pages/Categories';

function ProtectedRoute() {
  const { user, denied, loading } = useAuth();
  if (loading) {
    return <p className="py-20 text-center text-stone-500">Loading…</p>;
  }
  if (denied) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-trega-800 px-4">
        <div className="max-w-sm rounded-2xl bg-white p-8 text-center shadow-2xl">
          <h1 className="text-lg font-bold text-stone-900">Access denied</h1>
          <p className="mt-2 text-sm text-stone-500">
            This phone number is signed in but doesn't have the{' '}
            <span className="font-semibold">admin</span> custom claim. Ask the
            marketplace owner to grant it, then try again.
          </p>
          <a href="/login" className="mt-4 inline-block text-sm font-medium text-trega-600 hover:underline">
            ← Back to sign in
          </a>
        </div>
      </div>
    );
  }
  return user ? <Outlet /> : <Navigate to="/login" replace />;
}

export default function App() {
  return (
    <BrowserRouter>
      <AuthProvider>
        <Routes>
          <Route path="/login" element={<Login />} />
          <Route element={<ProtectedRoute />}>
            <Route element={<Layout />}>
              <Route index element={<Dashboard />} />
              <Route path="review" element={<ReviewQueue />} />
              <Route path="review/:id" element={<ListingDetail backTo="/review" />} />
              <Route path="listings" element={<Listings />} />
              <Route path="listings/:id" element={<ListingDetail backTo="/listings" />} />
              <Route path="users" element={<Users />} />
              <Route path="orders" element={<Orders />} />
              <Route path="bids" element={<Bids />} />
              <Route path="categories" element={<Categories />} />
            </Route>
          </Route>
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </AuthProvider>
    </BrowserRouter>
  );
}
