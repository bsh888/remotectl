import { Routes, Route } from 'react-router-dom'
import LandingPage from './pages/LandingPage'
import ControlPage from './pages/ControlPage'
import AdminPage from './pages/AdminPage'

export default function App() {
  return (
    <Routes>
      <Route path="/" element={<LandingPage />} />
      <Route path="/control" element={<ControlPage />} />
      <Route path="/admin/*" element={<AdminPage />} />
    </Routes>
  )
}
