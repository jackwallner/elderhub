-- Med List (Aging) — refill tracking on medications (plan82 slice B).
--
-- Quantity on hand, how many units make one dose, and the number of days of
-- supply left before we warn that a refill is due. All four are optional in
-- practice: `quantity_remaining = 0` means refills are not tracked for this
-- medication, not that the supply is empty (see `Medication.daysRemaining`
-- on the client, which returns nil in that case rather than zero).

alter table public.medications
    add column quantity_remaining     double precision not null default 0,
    add column units_per_dose         double precision not null default 1,
    add column refill_threshold_days  int not null default 7,
    add column last_filled_at         date;

notify pgrst, 'reload schema';
