import React from 'react'
import ReactDOM from 'react-dom/client'
import KedroApp from './App.jsx'
import UIMockup from './UIMockup.jsx'

const isMockup = new URLSearchParams(window.location.search).get('mock') === 'ui';

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    {isMockup ? <UIMockup /> : <KedroApp />}
  </React.StrictMode>
)
