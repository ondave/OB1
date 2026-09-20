from fastapi import APIRouter, HTTPException
from typing import List
from app.models.schemas import Item, ItemCreate

router = APIRouter()

# In-memory storage (replace with database in production)
items_db: List[Item] = []

@router.get("/items", response_model=List[Item])
async def get_items():
    """Get all items"""
    return items_db

@router.post("/items", response_model=Item)
async def create_item(item: ItemCreate):
    """Create a new item"""
    new_item = Item(id=len(items_db) + 1, **item.dict())
    items_db.append(new_item)
    return new_item

@router.get("/items/{item_id}", response_model=Item)
async def get_item(item_id: int):
    """Get a specific item by ID"""
    for item in items_db:
        if item.id == item_id:
            return item
    raise HTTPException(status_code=404, detail="Item not found")

@router.delete("/items/{item_id}")
async def delete_item(item_id: int):
    """Delete an item by ID"""
    for i, item in enumerate(items_db):
        if item.id == item_id:
            items_db.pop(i)
            return {"message": "Item deleted"}
    raise HTTPException(status_code=404, detail="Item not found")
