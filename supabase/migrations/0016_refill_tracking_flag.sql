-- Elderhub (Aging) — refill tracking gets a flag of its own.
--
-- 0009 overloaded `quantity_remaining = 0` to mean "refills are not tracked".
-- That collides with the supply actually reaching zero, which is the one moment
-- a refill warning is worth having: taking the last dose clamped the count to
-- zero, zero read as untracked, and the medication silently dropped out of the
-- Running low list, loaded with the toggle off in its editor, and could not
-- have the dose undone.
--
-- Backfilled from the old sentinel so every existing row keeps the meaning it
-- had: anything with stock on hand was being tracked, anything at zero was not.

alter table public.medications
    add column tracks_refills boolean not null default false;

update public.medications
   set tracks_refills = true
 where quantity_remaining > 0;

notify pgrst, 'reload schema';
