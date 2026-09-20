import { useState, useEffect } from 'react'
import axios from 'axios'
import './App.css'

interface Item {
  id: number
  name: string
  description?: string
}

function App() {
  const [items, setItems] = useState<Item[]>([])
  const [newItemName, setNewItemName] = useState('')
  const [newItemDescription, setNewItemDescription] = useState('')
  const [loading, setLoading] = useState(false)

  const API_URL = import.meta.env.VITE_API_URL || '/api'

  useEffect(() => {
    fetchItems()
  }, [])

  const fetchItems = async () => {
    try {
      const response = await axios.get(`${API_URL}/api/v1/items`)
      setItems(response.data)
    } catch (error) {
      console.error('Error fetching items:', error)
    }
  }

  const createItem = async () => {
    if (!newItemName.trim()) return

    setLoading(true)
    try {
      await axios.post(`${API_URL}/api/v1/items`, {
        name: newItemName,
        description: newItemDescription || undefined
      })
      setNewItemName('')
      setNewItemDescription('')
      await fetchItems()
    } catch (error) {
      console.error('Error creating item:', error)
    } finally {
      setLoading(false)
    }
  }

  const deleteItem = async (id: number) => {
    try {
      await axios.delete(`${API_URL}/api/v1/items/${id}`)
      await fetchItems()
    } catch (error) {
      console.error('Error deleting item:', error)
    }
  }

  return (
    <div className="App">
      <header className="App-header">
        <h1>{{APP_NAME}}</h1>
        <p>{{APP_DESCRIPTION}}</p>

        <div className="create-section">
          <h2>Create New Item</h2>
          <input
            type="text"
            placeholder="Item name"
            value={newItemName}
            onChange={(e) => setNewItemName(e.target.value)}
          />
          <input
            type="text"
            placeholder="Description (optional)"
            value={newItemDescription}
            onChange={(e) => setNewItemDescription(e.target.value)}
          />
          <button onClick={createItem} disabled={loading}>
            {loading ? 'Creating...' : 'Create Item'}
          </button>
        </div>

        <div className="items-section">
          <h2>Items</h2>
          {items.length === 0 ? (
            <p className="empty-state">No items yet. Create one above!</p>
          ) : (
            <ul className="items-list">
              {items.map((item) => (
                <li key={item.id} className="item">
                  <div className="item-content">
                    <strong>{item.name}</strong>
                    {item.description && <p>{item.description}</p>}
                  </div>
                  <button onClick={() => deleteItem(item.id)} className="delete-btn">
                    Delete
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>
      </header>
    </div>
  )
}

export default App
