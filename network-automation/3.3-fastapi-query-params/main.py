from fastapi import FastAPI

app = FastAPI()

fake_items_db = [{"item_name": f"Item {i}"} for i in range(1, 13)]


@app.get("/items/")
async def read_item(skip: int = 0, limit: int = 10):
    return fake_items_db[skip : skip + limit]
