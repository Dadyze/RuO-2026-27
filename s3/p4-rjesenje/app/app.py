import os
import redis
from flask import Flask

app = Flask(__name__)
r = redis.Redis(host=os.environ.get("REDIS_HOST", "redis"), port=6379)


@app.get("/")
def index():
    return f"Posjeta broj {r.incr('posjete')}\n"


@app.get("/health")
def health():
    return "ok\n"
