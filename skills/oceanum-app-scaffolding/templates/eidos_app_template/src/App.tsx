import { useState } from 'react'
import './App.css'

function App() {
  const [count, setCount] = useState(0)

  return (
    <div className="App">
      <header className="App-header">
        <h1>{{APP_NAME}}</h1>
        <p>{{APP_DESCRIPTION}}</p>
        <div className="card">
          <button onClick={() => setCount((count) => count + 1)}>
            count is {count}
          </button>
        </div>
        <p className="info">
          Edit <code>src/App.tsx</code> and save to test HMR
        </p>
      </header>
    </div>
  )
}

export default App
