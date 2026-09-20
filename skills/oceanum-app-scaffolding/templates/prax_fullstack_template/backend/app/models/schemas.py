from pydantic import BaseModel
from typing import Optional


class ItemCreate(BaseModel):
    """Schema for creating an item"""
    name: str
    description: Optional[str] = None


class Item(ItemCreate):
    """Schema for item with ID"""
    id: int

    class Config:
        from_attributes = True
