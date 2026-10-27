# Elderhub: Consumer Health Data Privacy Policy

> Consumer health data privacy policy for the Elderhub family medication app by Jack Wallner.

Web page: https://jackwallner.com/ios/elderhub/consumer-health-data.html

## Consumer Health Data Privacy Policy

Last updated: August 17, 2026

This policy is provided separately from the
[general privacy policy](https://jackwallner.com/ios/elderhub/privacy-policy.html) for people in
Washington State, under the My Health My Data Act, and for people in
Nevada under SB 370. It describes consumer health data specifically.
Everything here is also true of the general policy; nothing in one
contradicts the other.

Much of what Elderhub holds is consumer health data, and much of it is
about someone other than the person who typed it. The app also holds care
coordination and financial information that may be connected to that
health data. That is the point of the app, and it is why this page exists.

## Categories of Consumer Health Data Collected

- **Health conditions and status:** conditions, allergies,
  blood type, and free-text notes about a person's health.
- **Medications and treatment:** drug names, strengths,
  forms, what each medication is for, the prescribing doctor, the
  dispensing pharmacy, dosing schedules, and quantities on hand.
- **Use of health care services:** doctor visits, the reason
  for each, notes from them, follow-ups, and scheduled appointments.
- **Measurements:** vital signs typed in by a person, such as
  blood pressure, weight, temperature or blood sugar.
- **Health-related events:** falls, emergency room trips,
  symptoms and similar incidents recorded in the care log.
- **Bodily functions and daily activity:** whether a
  scheduled dose was taken or skipped, and the time a person pressed their
  daily check-in button.
- **Care coordination and family notes:** tasks, assignees,
  completion history, free-form notes, and bills recorded for a person's
  care. Bills may also be financial information. Elderhub does not store
  bank credentials or connect to a bank.
- **Identifiers connected to the above:** the name,
  relationship and date of birth of each person tracked, provider details,
  and emergency contact names and phone numbers.

**Elderhub does not collect precise location data.** The app
never requests location permission and contains no location code. It does
not collect biometric identifiers, does not read from Apple Health, and
does not connect to any monitor, wearable or medical device. Every value
in the app was typed in by a person.

## Sources of Consumer Health Data

One source only: what you and the other members of your care circle type
into the app. Elderhub does not buy, license, receive or infer health data
from any other party, and does not obtain it from data brokers, health
care providers, pharmacies, insurers or advertising networks.

## Purposes for Collecting and Using It

- To show you the medication list, emergency card, visit history, care
  events, tasks, notes, bills, and other records you entered.
- To sync that record between the phones of the people in your family
  group, so everyone looking after someone sees the same list.
- To send the local reminders and, if the daily check-in is turned on, to
  tell caregivers when a check-in did not happen in the agreed window.
- To keep the record available with no signal, which requires a full copy
  on the device.
- To let you choose whether to share an emergency-card copy through the
  iOS share sheet. That copy is sent to the app or person you choose, not
  automatically to Elderhub.

Consumer health data is **never** used for advertising, for
profiling, for training any model, for any form of behavioral analytics,
or for any purpose beyond running the features you turned on.

## Categories of Data Shared, and With Whom

**Elderhub does not sell consumer health data**, and has
never done so. Selling it, in the sense the My Health My Data Act uses,
would require your separate written authorization; there is no
circumstance in which it is offered for sale, so no such authorization is
ever sought.

Elderhub shares health data as part of operating the service in two ways:

- **With the other members of your own care circle.** This is
  the feature. Who can see what is set by each member's role, enforced by
  the database itself, and shown in full to a person before anything of
  theirs syncs. Organizers and caregivers can see the shared care records;
  a person in the being-supported role can see only permitted parts of
  their own record. Family notes and bills are staff-only.
- **With one processor, Supabase Inc.**, which hosts the
  encrypted database and the sync service on our behalf, under contract,
  and may not use the data for its own purposes. The shared database uses
  row-level access controls, but free-text notes and bill notes are not
  client-side or end-to-end encrypted. See
  [Supabase security](https://supabase.com/security).

Two other services are used for limited functions. Apple provides Sign in
with Apple, in-app purchases, and push notification delivery. A missed
check-in push contains the recipient's name and a factual no-check-in
message, not medication or diagnosis details. RevenueCat receives the
purchase receipt and linked app account identifier for subscription
checks, not the care record. No advertising network, data broker,
analytics vendor, or affiliate receives the care record, because there are
none.

## Storage and Retention

A record can remain local to one phone without an account or care circle.
When you explicitly share it, the app keeps a local offline copy and syncs
a shared copy to Supabase. The local store uses iOS file protection with
`NSFileProtectionCompleteUntilFirstUserAuthentication`; it is
not end-to-end encrypted. Deleted synced rows may remain as server
tombstones while the care circle exists, and an audit log can retain old
and new snapshots for medications, doses, people, and membership changes.

## Your Rights

You may, at any time and at no cost:

- **Confirm whether we hold your consumer health data, and access
  it.**
  Everything is visible in the app. The emergency card exports as plain
  text from inside it.
- **Learn the list of third parties it has been shared with.**
  That list is the section above, and it is complete.
- **Withdraw your consent** to its collection and sharing.
  Leaving your care circle stops that account's access and removes the
  shared copy from that phone. Deleting your account removes the account
  from the service, but does not erase the shared record kept for the rest
  of the family.
- **Have it deleted.** Delete individual entries in the app,
  or your whole account under Settings → Delete my account.
  Individual deletion is hidden in the app and follows the sync and audit
  retention rules above. Deleting your account deliberately does not erase
  the family's shared care record, which belongs to everyone looking after
  that person. To request deletion of the shared record, email the address
  below and it will be actioned within 30 days.

To exercise any of these by email, write to
[jackwallner+medlist@gmail.com](mailto:jackwallner+medlist@gmail.com). A request is verified by confirming control of the email address or
Apple relay address on the account. There is no fee, and exercising a
right will never result in a worse experience in the app.

If a request is refused, the reason will be given in the reply, and you
may appeal by replying to it. If an appeal is denied you may complain to
the
[Washington State Attorney General](https://www.atg.wa.gov/file-complaint).

## Data About Other People

Most of what is in Elderhub is health data about someone other than the
person who entered it. When you add a person who will not be using the app
themselves, Elderhub asks you to confirm that they know you keep this
record or that you are the person who makes their health decisions, and
records that confirmation. Please enter someone else's health information
only if that is true. A person who later joins with their own account is
shown exactly who is in the group and what each member can see about them,
before anything of theirs syncs, and may leave at any time.

## Changes

Material changes to this policy will be posted here with a revised date
before they take effect, and consumer health data already collected will
not be used for a new purpose without consent.

## Contact

Jack Wallner
[jackwallner+medlist@gmail.com](mailto:jackwallner+medlist@gmail.com)

[Privacy Policy](https://jackwallner.com/ios/elderhub/privacy-policy.html) ·
[Support](https://jackwallner.com/ios/elderhub/support.html) ·
[Terms of Use](https://jackwallner.com/ios/elderhub/terms.html)

[Home](https://jackwallner.com/ios/elderhub/)
[Privacy](https://jackwallner.com/ios/elderhub/privacy-policy.html)
[Terms](https://jackwallner.com/ios/elderhub/terms.html)
[Support](https://jackwallner.com/ios/elderhub/support.html)
