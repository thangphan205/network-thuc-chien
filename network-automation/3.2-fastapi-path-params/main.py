# https://fastapi.tiangolo.com/tutorial/path-params/

from fastapi import FastAPI

app = FastAPI()


@app.get("/items/{item_id}")
async def read_item(item_id):
    # item_id will be passed to the function as a string
    # Xử lý item_id ở đây
    return {"item_id": item_id}


@app.get("/items2/{item_id}")
async def read_item2(item_id: int):
    # item_id will be passed to the function as an integer
    # Xử lý item_id ở đây
    return {"item_id": item_id}
