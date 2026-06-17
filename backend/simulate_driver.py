"""
============================================================
  SIMULATEUR DE POSITION CHAUFFEUR - SmartPickup
============================================================
  Usage:
    python simulate_driver.py --ride-id <ID> [options]

  Exemples:
    python simulate_driver.py --ride-id 5
    python simulate_driver.py --ride-id 5 --from-lat 36.8065 --from-lng 10.1815 --to-lat 36.8200 --to-lng 10.2000
    python simulate_driver.py --ride-id 5 --interval 1 --steps 30
    python simulate_driver.py --ride-id 5 --server ws://192.168.1.10:8000

  Ce script se connecte au WebSocket du backend comme un chauffeur
  et envoie des coordonnées GPS en mouvement progressif.
  Il ne modifie AUCUN fichier du projet.
============================================================
"""

import asyncio
import json
import math
import argparse
from datetime import datetime

try:
    import websockets
except ImportError:
    print("❌ Module 'websockets' manquant. Installez-le avec:")
    print("   pip install websockets")
    exit(1)


# ─── Couleurs terminal ─────────────────────────────────────
GREEN  = "\033[92m"
YELLOW = "\033[93m"
RED    = "\033[91m"
CYAN   = "\033[96m"
BOLD   = "\033[1m"
RESET  = "\033[0m"


def haversine_distance(lat1, lng1, lat2, lng2):
    """Calcule la distance en km entre deux points GPS."""
    R = 6371
    dlat = math.radians(lat2 - lat1)
    dlng = math.radians(lng2 - lng1)
    a = math.sin(dlat/2)**2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlng/2)**2
    return R * 2 * math.asin(math.sqrt(a))


def interpolate_path(from_lat, from_lng, to_lat, to_lng, steps):
    """Génère une liste de coordonnées entre deux points avec un léger bruit réaliste."""
    import random
    points = []
    for i in range(steps + 1):
        t = i / steps
        # Interpolation linéaire
        lat = from_lat + (to_lat - from_lat) * t
        lng = from_lng + (to_lng - from_lng) * t
        # Petit bruit GPS réaliste (±0.00005 degrés ≈ ±5 mètres)
        lat += random.gauss(0, 0.00003)
        lng += random.gauss(0, 0.00003)
        points.append((round(lat, 6), round(lng, 6)))
    return points


async def simulate(args):
    ws_url = f"{args.server}/rides/{args.ride_id}/ws"
    
    points = interpolate_path(
        args.from_lat, args.from_lng,
        args.to_lat,   args.to_lng,
        args.steps
    )
    
    total_dist = haversine_distance(args.from_lat, args.from_lng, args.to_lat, args.to_lng)
    
    print(f"\n{BOLD}{CYAN}{'='*55}{RESET}")
    print(f"{BOLD}{CYAN}  🚕 SIMULATEUR CHAUFFEUR - SmartPickup{RESET}")
    print(f"{CYAN}{'='*55}{RESET}")
    print(f"  {BOLD}URL WebSocket :{RESET} {ws_url}")
    print(f"  {BOLD}Course ID     :{RESET} #{args.ride_id}")
    print(f"  {BOLD}Départ        :{RESET} {args.from_lat}, {args.from_lng}")
    print(f"  {BOLD}Arrivée       :{RESET} {args.to_lat}, {args.to_lng}")
    print(f"  {BOLD}Distance      :{RESET} {total_dist:.2f} km")
    print(f"  {BOLD}Étapes        :{RESET} {args.steps} points")
    print(f"  {BOLD}Intervalle    :{RESET} {args.interval}s → durée ≈ {args.steps * args.interval}s")
    print(f"{CYAN}{'='*55}{RESET}\n")
    
    print(f"  {YELLOW}Connexion au serveur...{RESET}")
    
    try:
        async with websockets.connect(ws_url, ping_interval=20, ping_timeout=10) as ws:
            print(f"  {GREEN}✅ Connecté ! Début de la simulation...{RESET}\n")
            
            for idx, (lat, lng) in enumerate(points):
                progress = int((idx / len(points)) * 30)
                bar = "█" * progress + "░" * (30 - progress)
                pct = int((idx / len(points)) * 100)
                
                payload = {
                    "lat": lat,
                    "lng": lng,
                    "timestamp": datetime.now().isoformat(),
                    "ride_id": args.ride_id,
                    "simulated": True,
                    "step": idx + 1,
                    "total_steps": len(points)
                }
                
                await ws.send(json.dumps(payload))
                
                # Affichage progression
                print(f"\r  [{bar}] {pct:3d}% | Point {idx+1}/{len(points)} | "
                      f"📍 {lat:.5f}, {lng:.5f}", end="", flush=True)
                
                if idx < len(points) - 1:
                    await asyncio.sleep(args.interval)
            
            print(f"\n\n  {GREEN}{BOLD}✅ Simulation terminée ! {len(points)} positions envoyées.{RESET}")
            print(f"  {YELLOW}La carte du passager devrait avoir suivi la route.{RESET}\n")
            
            # Garder la connexion ouverte 3s avant de fermer
            await asyncio.sleep(3)
            
    except ConnectionRefusedError:
        print(f"\n  {RED}❌ Connexion refusée. Le serveur backend est-il démarré ?{RESET}")
        print(f"  {RED}   Vérifiez que uvicorn tourne sur {args.server.replace('ws://', 'http://')}{RESET}\n")
    except websockets.exceptions.WebSocketException as e:
        print(f"\n  {RED}❌ Erreur WebSocket: {e}{RESET}\n")
    except Exception as e:
        print(f"\n  {RED}❌ Erreur inattendue: {e}{RESET}\n")


def main():
    parser = argparse.ArgumentParser(
        description="[SmartPickup] Simulateur de position chauffeur - envoie des coordonnees GPS via WebSocket",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Exemples:\n  python simulate_driver.py --ride-id 5\n  python simulate_driver.py --ride-id 5 --from-lat 36.8065 --from-lng 10.1815 --to-lat 36.82 --to-lng 10.22 --steps 30"
    )
    
    parser.add_argument(
        "--ride-id", "-r",
        type=int,
        required=True,
        help="ID de la course à simuler (request_id dans la BD)"
    )
    parser.add_argument(
        "--server", "-s",
        type=str,
        default="ws://localhost:8000",
        help="URL du serveur WebSocket (défaut: ws://localhost:8000)"
    )
    parser.add_argument(
        "--from-lat",
        type=float,
        default=36.8065,
        help="Latitude de départ (défaut: Tunis centre)"
    )
    parser.add_argument(
        "--from-lng",
        type=float,
        default=10.1815,
        help="Longitude de départ (défaut: Tunis centre)"
    )
    parser.add_argument(
        "--to-lat",
        type=float,
        default=36.8500,
        help="Latitude d'arrivée (défaut: Tunis nord)"
    )
    parser.add_argument(
        "--to-lng",
        type=float,
        default=10.2200,
        help="Longitude d'arrivée (défaut: Tunis nord)"
    )
    parser.add_argument(
        "--steps", "-n",
        type=int,
        default=20,
        help="Nombre de points GPS à envoyer (défaut: 20)"
    )
    parser.add_argument(
        "--interval", "-i",
        type=float,
        default=2.0,
        help="Intervalle en secondes entre chaque point (défaut: 2)"
    )
    
    args = parser.parse_args()
    
    try:
        asyncio.run(simulate(args))
    except KeyboardInterrupt:
        print(f"\n  {YELLOW}⚠️  Simulation interrompue par l'utilisateur.{RESET}\n")


if __name__ == "__main__":
    main()
