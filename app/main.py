from fastapi import FastAPI


app = FastAPI()


@app.get("/")
async def root():    
    return {"message": "Hello DEVOPS World"}

@app.get("/health")
async def health():    
    return {"status": "running"}