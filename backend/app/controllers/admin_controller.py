from fastapi import HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import func, cast, Date
from datetime import datetime, timedelta
from app.models.user import User
from app.models.ride_request import RideRequest
from app.models.ride_log import RideLog
from app.models.incident_rapport import IncidentReport
from app.models.base_enums import UserRoleEnum, RideStatusEnum

class AdminController:
    @staticmethod
    def get_stats(db: Session):
        try:
            total_rides     = db.query(func.count(RideRequest.request_id)).scalar() or 0
            total_users     = db.query(func.count(User.user_id)).filter(User.role == UserRoleEnum.commuter).scalar() or 0
            total_drivers   = db.query(func.count(User.user_id)).filter(User.role == UserRoleEnum.driver).scalar() or 0
            active_rides    = db.query(func.count(RideRequest.request_id)).filter(RideRequest.status == RideStatusEnum.ACCEPTED).scalar() or 0
            completed_rides = db.query(func.count(RideRequest.request_id)).filter(RideRequest.status == RideStatusEnum.COMPLETED).scalar() or 0
            pending_rides   = db.query(func.count(RideRequest.request_id)).filter(RideRequest.status == RideStatusEnum.PENDING).scalar() or 0
            cancelled_rides = db.query(func.count(RideRequest.request_id)).filter(RideRequest.status == RideStatusEnum.CANCELLED).scalar() or 0
            pending_drivers = db.query(func.count(User.user_id)).filter(User.role == UserRoleEnum.driver, User.is_active == False).scalar() or 0
            active_drivers  = db.query(func.count(User.user_id)).filter(User.role == UserRoleEnum.driver, User.is_active == True).scalar() or 0

            # Revenue from ride_logs (amount actually paid)
            total_revenue = db.query(func.coalesce(func.sum(RideLog.amount_paid_cash), 0)).scalar() or 0

            return {
                "total_rides":     total_rides,
                "total_users":     total_users,
                "total_drivers":   total_drivers,
                "active_drivers":  active_drivers,
                "active_rides":    active_rides,
                "completed_rides": completed_rides,
                "pending_rides":   pending_rides,
                "cancelled_rides": cancelled_rides,
                "pending_drivers": pending_drivers,
                "total_revenue":   float(total_revenue),
            }
        except Exception as e:
            raise HTTPException(status_code=500, detail=str(e))

    @staticmethod
    def get_pending_drivers(db: Session):
        return db.query(User).filter(
            User.role == UserRoleEnum.driver,
            User.is_active == False
        ).all()

    @staticmethod
    def approve_driver(db: Session, driver_id: int):
        driver = db.query(User).filter(User.user_id == driver_id, User.role == UserRoleEnum.driver).first()
        if not driver:
            raise HTTPException(status_code=404, detail="Driver not found")
        driver.is_active = True
        db.commit()
        return {"message": f"Driver {driver.full_name} approved successfully"}

    @staticmethod
    def get_recent_rides(db: Session, limit: int):
        return db.query(RideRequest).order_by(RideRequest.requested_at.desc()).limit(limit).all()

    @staticmethod
    def get_analytics(db: Session):
        """
        Analytics strictly based on real DB tables:
          - ride_requests  → courses par jour + statuts
          - ride_logs      → revenu par jour (amount_paid_cash)
          - incident_reports → incidents par jour + statuts
          - users          → répartition chauffeurs actifs/inactifs
        """
        try:
            today = datetime.utcnow().date()
            days  = [(today - timedelta(days=i)) for i in range(6, -1, -1)]  # oldest → newest
            labels = [d.strftime('%a %d/%m') for d in days]

            # ── 1. Courses par jour (ride_requests.requested_at) ─────────────
            rides_rows = (
                db.query(
                    cast(RideRequest.requested_at, Date).label('day'),
                    func.count(RideRequest.request_id).label('cnt')
                )
                .filter(cast(RideRequest.requested_at, Date) >= days[0])
                .group_by(cast(RideRequest.requested_at, Date))
                .all()
            )
            rides_map = {str(r.day): int(r.cnt) for r in rides_rows}
            rides_per_day = [rides_map.get(str(d), 0) for d in days]

            # ── 2. Revenu par jour (ride_logs.amount_paid_cash) ──────────────
            rev_rows = (
                db.query(
                    cast(RideLog.start_time, Date).label('day'),
                    func.coalesce(func.sum(RideLog.amount_paid_cash), 0).label('rev')
                )
                .filter(cast(RideLog.start_time, Date) >= days[0])
                .group_by(cast(RideLog.start_time, Date))
                .all()
            )
            rev_map = {str(r.day): float(r.rev) for r in rev_rows}
            revenue_per_day = [rev_map.get(str(d), 0.0) for d in days]

            # ── 3. Incidents par jour (incident_reports — no timestamp → total) ─
            # IncidentReport n'a pas de colonne date, on ne peut que compter le total
            total_incidents  = db.query(func.count(IncidentReport.report_id)).scalar() or 0
            open_incidents   = db.query(func.count(IncidentReport.report_id)).filter(IncidentReport.status == 'OPEN').scalar() or 0
            closed_incidents = db.query(func.count(IncidentReport.report_id)).filter(IncidentReport.status != 'OPEN').scalar() or 0

            # ── 4. Répartition des statuts de courses ────────────────────────
            completed = db.query(func.count(RideRequest.request_id)).filter(RideRequest.status == RideStatusEnum.COMPLETED).scalar() or 0
            cancelled = db.query(func.count(RideRequest.request_id)).filter(RideRequest.status == RideStatusEnum.CANCELLED).scalar() or 0
            pending   = db.query(func.count(RideRequest.request_id)).filter(RideRequest.status == RideStatusEnum.PENDING).scalar() or 0
            accepted  = db.query(func.count(RideRequest.request_id)).filter(RideRequest.status == RideStatusEnum.ACCEPTED).scalar() or 0

            # ── 5. Chauffeurs actifs vs inactifs ─────────────────────────────
            active_drivers   = db.query(func.count(User.user_id)).filter(User.role == UserRoleEnum.driver, User.is_active == True).scalar() or 0
            inactive_drivers = db.query(func.count(User.user_id)).filter(User.role == UserRoleEnum.driver, User.is_active == False).scalar() or 0

            # ── 6. Taux de complétion (%) ────────────────────────────────────
            total_rides = completed + cancelled + pending + accepted
            completion_rate = round(completed / max(total_rides, 1) * 100, 1)
            cancellation_rate = round(cancelled / max(total_rides, 1) * 100, 1)

            return {
                "labels": labels,
                # Courbes 7 jours
                "rides_per_day":   rides_per_day,
                "revenue_per_day": revenue_per_day,
                # Répartition statuts (donut)
                "ride_status": {
                    "completed": completed,
                    "cancelled": cancelled,
                    "pending":   pending,
                    "accepted":  accepted,
                },
                # Taux
                "completion_rate":   completion_rate,
                "cancellation_rate": cancellation_rate,
                # Chauffeurs
                "drivers": {
                    "active":   active_drivers,
                    "inactive": inactive_drivers,
                },
                # Incidents
                "incidents": {
                    "total":  total_incidents,
                    "open":   open_incidents,
                    "closed": closed_incidents,
                },
            }
        except Exception as e:
            raise HTTPException(status_code=500, detail=str(e))
