"""
Campus Bid - vector search service.

What is embedded : one document per task = "<category>: <title>. <description>"
Model            : all-MiniLM-L6-v2 (Chroma's default embedding function, runs locally via ONNX), 384 dimensions
Storage          : Chroma persistent collection "tasks" (on disk in ./chroma_data), HNSW index
Metadata         : task_id, category, budget, status, poster_id (usable in `where` filters)
Similarity       : cosine  (score = 1 - cosine distance, so 1.0 = identical meaning)
Retrieval        : embed the query with the same model, return the top-k nearest tasks

CRUD on the vector store
  Create/Update : POST   /index           (upsert by task id)
  Read          : POST   /search          (semantic search)
                  GET    /similar/{id}    (tasks similar to a stored task)
                  GET    /task/{id}       (stored document + metadata)
  Delete        : DELETE /task/{id}

Run:  uvicorn main:app --port 8000
"""
import os

import chromadb
from chromadb.utils import embedding_functions
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

DATA_DIR = os.environ.get("CHROMA_PATH", "./chroma_data")

client = chromadb.PersistentClient(path=DATA_DIR)
embedder = embedding_functions.DefaultEmbeddingFunction()  # all-MiniLM-L6-v2

try:  # chromadb >= 1.0
    collection = client.get_or_create_collection(
        "tasks", configuration={"hnsw": {"space": "cosine"}}, embedding_function=embedder
    )
except TypeError:  # older chromadb
    collection = client.get_or_create_collection(
        "tasks", metadata={"hnsw:space": "cosine"}, embedding_function=embedder
    )

app = FastAPI(title="Campus Bid vector service")


class TaskIn(BaseModel):
    task_id: int
    title: str
    description: str = ""
    category: str = ""
    budget: float = 0
    status: str = "open"
    poster_id: int = 0


class SearchIn(BaseModel):
    query: str
    k: int = 5
    status: str | None = None


def to_document(t: TaskIn) -> str:
    return f"{t.category}: {t.title}. {t.description}".strip()


def hits(res) -> list[dict]:
    out = []
    for id_, dist, meta in zip(res["ids"][0], res["distances"][0], res["metadatas"][0]):
        out.append({"task_id": int(id_), "score": round(1 - float(dist), 4), "metadata": meta})
    return out


@app.get("/health")
def health():
    return {"ok": True, "count": collection.count()}


@app.post("/index")
def index_task(t: TaskIn):
    """Create or update (upsert) the vector for one task."""
    collection.upsert(
        ids=[str(t.task_id)],
        documents=[to_document(t)],
        metadatas=[{
            "task_id": t.task_id, "category": t.category, "budget": t.budget,
            "status": t.status, "poster_id": t.poster_id,
        }],
    )
    return {"indexed": t.task_id, "count": collection.count()}


@app.post("/search")
def search(s: SearchIn):
    n = collection.count()
    if n == 0 or not s.query.strip():
        return {"results": []}
    res = collection.query(
        query_texts=[s.query],
        n_results=max(1, min(s.k, n)),
        where={"status": s.status} if s.status else None,
    )
    return {"results": hits(res)}


@app.get("/similar/{task_id}")
def similar(task_id: int, k: int = 4):
    got = collection.get(ids=[str(task_id)], include=["embeddings"])
    if len(got["ids"]) == 0:
        raise HTTPException(404, "task is not indexed")
    emb = got["embeddings"][0]
    emb = emb.tolist() if hasattr(emb, "tolist") else list(emb)
    n = collection.count()
    res = collection.query(query_embeddings=[emb], n_results=min(k + 1, n))
    return {"results": [h for h in hits(res) if h["task_id"] != task_id][:k]}


@app.get("/task/{task_id}")
def get_task(task_id: int):
    got = collection.get(ids=[str(task_id)], include=["documents", "metadatas"])
    if len(got["ids"]) == 0:
        raise HTTPException(404, "task is not indexed")
    return {"task_id": task_id, "document": got["documents"][0], "metadata": got["metadatas"][0]}


@app.delete("/task/{task_id}")
def delete_task(task_id: int):
    collection.delete(ids=[str(task_id)])
    return {"deleted": task_id, "count": collection.count()}
