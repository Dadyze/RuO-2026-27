import os
import redis
from flask import Flask

app = Flask(__name__)
r = redis.Redis(host=os.environ.get("REDIS_HOST", "redis"), port=6379)
# Provjera spremnosti ima svoj timeout i ne mijenja klijent brojaca.
ready_redis = redis.Redis(
    host=os.environ.get("REDIS_HOST", "redis"),
    port=6379,
    socket_connect_timeout=0.5,
    socket_timeout=0.5,
)


@app.get("/")
def index():
    return f"Posjeta broj {r.incr('posjete')}\n"


@app.get("/health")
def health():
    return "ok\n"


@app.get("/ready")
def ready():
    # Pad Redisa ne znaci da treba restartovati web aplikaciju.
    try:
        ready_redis.ping()
    except redis.exceptions.RedisError:
        return "Redis nije dostupan\n", 503
    return "ok\n"
