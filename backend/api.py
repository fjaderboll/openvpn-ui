import io
import os
import zipfile
from datetime import datetime

from fastapi import APIRouter, HTTPException, Depends, UploadFile, File
from fastapi.responses import Response, StreamingResponse

from backend.auth import verify_token
from backend.models import ClientCreate
from backend import openvpn

router = APIRouter()


@router.get("/clients")
async def list_clients(user: str = Depends(verify_token)):
    return openvpn.list_clients()


@router.post("/clients")
async def create_client(client: ClientCreate, user: str = Depends(verify_token)):
    assignments = openvpn.get_ip_assignments()
    if client.name in assignments:
        raise HTTPException(status_code=400, detail="Client already exists")

    try:
        config = openvpn.generate_client(client.name)
    except RuntimeError as e:
        raise HTTPException(status_code=500, detail=str(e))

    return {"name": client.name, "config": config}


@router.get("/clients/{name}/config")
async def download_config(name: str, user: str = Depends(verify_token)):
    ovpn_path = openvpn.CLIENTS_DIR / f"{name}.ovpn"
    if not ovpn_path.exists():
        raise HTTPException(status_code=404, detail="Client config not found")

    return Response(
        content=ovpn_path.read_text(),
        media_type="application/x-openvpn-profile",
        headers={"Content-Disposition": f'attachment; filename="{name}.ovpn"'},
    )


@router.delete("/clients/{name}")
async def delete_client(name: str, user: str = Depends(verify_token)):
    assignments = openvpn.get_ip_assignments()
    if name not in assignments:
        raise HTTPException(status_code=404, detail="Client not found")

    try:
        openvpn.revoke_client(name)
        openvpn.restart_openvpn()
    except RuntimeError as e:
        raise HTTPException(status_code=500, detail=str(e))

    return {"status": "revoked", "name": name}


@router.get("/backup")
async def download_backup(user: str = Depends(verify_token)):
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as zf:
        for dir_name in ["pki", "ccd", "config", "clients"]:
            dir_path = openvpn.DATA_DIR / dir_name
            if dir_path.exists():
                for file_path in dir_path.rglob("*"):
                    if file_path.is_file():
                        arcname = str(file_path.relative_to(openvpn.DATA_DIR))
                        zf.write(file_path, arcname)

        ip_file = openvpn.DATA_DIR / "ip_assignments.json"
        if ip_file.exists():
            zf.write(ip_file, "ip_assignments.json")

    buffer.seek(0)
    date_str = datetime.now().strftime("%Y-%m-%d")
    filename = f"openvpn-backup-{date_str}.zip"
    return StreamingResponse(
        buffer,
        media_type="application/zip",
        headers={
            "Content-Disposition": f'attachment; filename="{filename}"'
        },
    )


@router.post("/backup/restore")
async def restore_backup(
    file: UploadFile = File(...), user: str = Depends(verify_token)
):
    content = await file.read()
    buffer = io.BytesIO(content)

    try:
        with zipfile.ZipFile(buffer, "r") as zf:
            # Validate: no path traversal
            for info in zf.infolist():
                if info.filename.startswith("/") or ".." in info.filename:
                    raise HTTPException(
                        status_code=400,
                        detail="Invalid backup file: suspicious paths detected",
                    )

            # Validate: must contain PKI data
            names = zf.namelist()
            if not any(n.startswith("pki/") for n in names):
                raise HTTPException(
                    status_code=400,
                    detail="Invalid backup file: missing PKI data",
                )

            # Extract to data directory
            zf.extractall(openvpn.DATA_DIR)
    except zipfile.BadZipFile:
        raise HTTPException(status_code=400, detail="Invalid zip file")

    # Fix CRL permissions
    crl_path = openvpn.PKI_DIR / "crl.pem"
    if crl_path.exists():
        os.chmod(crl_path, 0o644)

    openvpn.restart_openvpn()
    return {"status": "restored"}


@router.get("/logs")
async def get_logs(lines: int = 100, user: str = Depends(verify_token)):
    if lines < 1 or lines > 10000:
        lines = 100
    return {"logs": openvpn.get_logs(lines)}


@router.get("/server/status")
async def server_status(user: str = Depends(verify_token)):
    connected = openvpn.get_connected_clients()
    return {
        "clients_connected": len(connected),
        "connected_clients": list(connected.keys()),
    }
