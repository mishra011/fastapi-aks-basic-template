from datetime import datetime
from zoneinfo import ZoneInfo

from fastapi import FastAPI


app = FastAPI()


@app.get("/")
async def root():
    now_ist = datetime.now(ZoneInfo("Asia/Kolkata"))
    return {
        "message": f"Hello DEVOPS World! Current IST date and time: {now_ist.strftime('%Y-%m-%d %H:%M:%S IST')}",
    }

@app.get("/health")
async def health():    
    return {"status": "running"}
