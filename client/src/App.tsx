import { Routes, Route } from 'react-router-dom'
import LandingPage from './pages/LandingPage'
import ControlPage from './pages/ControlPage'
import AdminPage from './pages/AdminPage'
import { I18nContext, useI18nProvider } from './i18n'

export default function App() {
  const i18n = useI18nProvider()
  return (
    <I18nContext.Provider value={i18n}>
      <Routes>
        <Route path="/" element={<LandingPage />} />
        <Route path="/control" element={<ControlPage />} />
        <Route path="/admin/*" element={<AdminPage />} />
      </Routes>
    </I18nContext.Provider>
  )
}
