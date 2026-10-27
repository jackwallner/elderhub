# Elderhub - Privacy Policy

> Privacy policy for the Elderhub family medication app by Jack Wallner.

Web page: https://jackwallner.com/ios/elderhub/privacy-policy.html

## Elderhub Privacy Policy

Last updated: October 21, 2026

## Overview

Elderhub is an iPhone app for keeping a care record for a parent, partner,
or another person you help. It records medications and other health
information, along with care tasks, notes, bills, contacts, and family
sharing. Much of what is in it is information about someone other than the
person typing it, so it is treated accordingly.

If you are in Washington State or Nevada, the
[Consumer Health Data Privacy Policy](https://jackwallner.com/ios/elderhub/consumer-health-data.html)
covers the same app in the specific terms those laws ask for, including
how to withdraw consent and how to have data deleted.

## The Android App

Elderhub for Android works without an account. Until you sign in, the
people, medications, doses, appointments, contacts, and providers you
enter stay in the app's private storage on the phone, are excluded from
Android cloud backup and device transfer, and are deleted when you
uninstall the app or clear its storage. Dose reminders are local
notifications scheduled on the phone; nothing is sent to show them.

Family sharing on Android uses **Sign in with Google**.
Google gives Elderhub a sign-in token containing your Google account
identifier, name, and email address, and the Supabase account created
from it stores them. Elderhub never receives your Google password, and
asks for nothing Google has already provided. An Android account and an
iPhone account (Sign in with Apple) are separate accounts, even for the
same person; Elderhub does not link or merge them.

Once you start or join a care circle, the records you share (people,
medications and dose history, visits and appointments, emergency
contacts, and providers) are stored in Supabase and shared with the
members of that circle exactly as described below for the iPhone app,
under the same access rules. Records you keep only on this phone are
never uploaded unless you choose to share them. The Android app shows
when a person last pressed their check-in button after it syncs; it does
not register for push notifications and receives no Firebase or Google
push token.

Purchases in the Android app are processed by **Google Play**.
Elderhub never receives payment card details. **RevenueCat**
receives the Google Play purchase token, product, and an app user
identifier (anonymous until you sign in, then your Supabase account
identifier so a care circle can receive its entitlement), to verify the
subscription or lifetime purchase. It does not receive the care record.
Manage or cancel a subscription in Google Play under Payments &
subscriptions. Where the sections below mention Apple, StoreKit, or
Apple push notifications, they describe the iPhone app.

## What Elderhub Collects

Elderhub collects information you enter, information needed to operate a
care circle, and information needed for notifications and purchases.

- **Account and care circle:** your display name, Supabase
  account identifier, care-circle name, membership, role, and membership
  dates. Sign in with Apple creates an account. Apple may share your name
  and a private-relay email address. Elderhub never receives your Apple ID
  password. Sign in with Apple is the only sign-in method on iPhone; the
  Android app uses Sign in with Google.
- **Invitations:** an invitation email address, invite code,
  intended role or person, and the invitation's created, used, revoked,
  and expiry state. Invitation attempts are also recorded to protect codes
  from guessing.
- **People you track:** name, relationship, date of birth,
  blood type, allergies, conditions, free-text notes, and the time a
  caregiver confirmed that the person knows about the record or that the
  caregiver makes their health decisions.
- **Medications and doses:** drug names, strengths, forms,
  schedules, what a medication is for, prescriber and pharmacy details,
  instructions, active dates, as-needed status, refill quantities and
  thresholds, and a record of which doses were marked taken, skipped, or
  missed, when, with any note, and by whom.
- **Visits, providers, readings, and care events:** visit
  dates, doctors, specialties, reasons, notes, follow-ups, appointments,
  provider and pharmacy names, specialties, phone numbers, addresses,
  portal links and notes, vital signs, and events such as falls, symptoms,
  mood, appetite, sleep, or pain, including their severity and who logged
  them.
- **Tasks, notes, and bills:** task titles, notes, due dates,
  priorities, recurrence, assignees, and completion history; standalone
  note titles, bodies, and pin status; and bill payees, amounts, notes,
  categories, recurrence, due dates, autopay status, and who marked a bill
  paid. Bills are a record that a person says they paid. Elderhub does not
  connect to a bank, make payments, or provide fields for account numbers,
  card numbers, or passwords.
- **Emergency contacts:** names and phone numbers you enter
  for the emergency card.
- **Check-ins:** the time a person pressed their daily
  check-in button, who recorded it, and the agreed window and time zone it
  should happen in.
- **Notifications:** an Apple Push Notification service
  device token, so the server can tell caregivers when a check-in did not
  happen. That push contains the recipient's name and a factual
  no-check-in message, not medication or diagnosis details.
- **Purchases:** StoreKit and RevenueCat purchase, receipt,
  product, subscription, and entitlement information, linked to the
  Supabase account identifier so a care circle can receive its
  entitlement.

**Elderhub does not collect location.** The app never asks
for it and contains no location code. It does not read Apple Health or
connect to a monitor, wearable, or medical device; readings and events are
typed in by a person. There is no advertising SDK or behavioral analytics.
Nothing is sold and nothing is used for tracking.

## Information About Other People

Most of what you enter is about someone else. When you add a person who
will not use the app themselves, Elderhub asks you to confirm that they
know you are keeping this record, or that you are the person who makes
their health decisions. Please only enter someone else's health
information if that is true.

Elderhub does not assess anyone's ability to make their own decisions.
That is a clinical judgment and this app does not make it.

A person who joins the care circle with their own account is shown, before
anything syncs, exactly who is in the circle and what each member can see
about them. They can see that page again at any time, and they can leave
whenever they want.

A record can remain local to one phone without an account or care circle.
It is not uploaded merely because the app is installed. Sharing is an
explicit choice that adopts the record into a care circle.

## How Data Is Stored

Elderhub has a local store and, only when you choose to share a record, a
shared store. The local store is a full working copy of the care record,
including the records needed for offline use, so the app opens with no
signal.

The local SwiftData store is protected by iOS with
`NSFileProtectionCompleteUntilFirstUserAuthentication`. This
protects the files until you first enter your passcode after a reboot. After
that, iOS may make them available while the phone is locked so offline
reads, background sync, and local notifications can work. The care record
is not end-to-end or client-side encrypted.

The shared copy is stored on **Supabase** in Postgres,
encrypted in transit and at rest. Access is enforced per row by the
database itself as well as by the app: a member of one family cannot read
another family's record. Free-text notes and bill notes are ordinary
plaintext fields protected by these access rules, not a password vault.
Supabase processes the data to provide authentication, storage, and sync.
See [Supabase security](https://supabase.com/security).

To make offline sync and family history work, edited or deleted synced
rows carry server timestamps and deletion markers. Deleted rows are hidden
from the app but may remain as server tombstones while the care circle
exists. For medications, doses, people, and membership changes, an audit
log can retain old and new snapshots and the name recorded for the person
who made the change.

## Who Can See What

- **Organizer** and **caregiver** see and edit
  the shared care records for everyone in their own care circle. This
  includes health records, tasks, notes, and bills. The organizer also
  controls membership and billing.
- **Being supported** can see only the permitted parts of
  their own record, including medications, doses, visits, readings,
  contacts, providers, care events, tasks, and check-ins. Family notes and
  bills are staff-only. They can mark their own doses and press their own
  check-in button, but cannot edit the shared health record.
- Nobody outside your care circle can see anything in it.

Device handover is a local phone setting, not a change to account
permissions. In recipient mode, the selected person sees a read-only
check-in screen, their medications, and the emergency card. The emergency
card is never behind the caregiver code.

## The Check-in Feature

If a daily check-in is turned on and the button is not pressed by the end
of the agreed window, the app tells the caregivers in that group that no
check-in happened. That is the whole feature. Elderhub does not detect
falls or emergencies, does not decide that anything is wrong, and does not
call anyone for help.

## Notifications

Check-in, medication, and refill reminders are scheduled on the device
itself. The message to caregivers about a missed check-in is a push
notification sent from the server. You can turn notifications off in iOS
Settings > Notifications > Elderhub.

## Purchases & Subscriptions

The purchase is processed by **Apple StoreKit**. Elderhub
never receives payment card details, billing address, or Apple ID
credentials. **RevenueCat** receives the purchase receipt and
the linked app account identifier to verify product, subscription, and
entitlement status. It does not receive the care record or a payment
profile. See
[RevenueCat Privacy](https://www.revenuecat.com/privacy).
Subscription management and refunds are handled in your Apple ID account
settings.

## Third-Party Services

- **Apple:** Sign in with Apple, in-app purchases, and push
  notification delivery. Apple receives the information needed for those
  services, including push content and the device token.
- **Supabase:** account authentication, profiles, care-circle
  membership, database storage, server-side check-in processing, and sync
- **RevenueCat:** purchase receipt and subscription
  entitlement checks, linked to the Supabase account identifier

## Retention & Deletion

Deleting your account (Settings > Delete my account, or by email) removes
your account from the service and unlinks it from any care-recipient
record. It deliberately does not delete the family's shared care record:
that record belongs to everyone looking after that person, and one member
leaving should not erase it for the others. Entries and audit records can
keep the display name recorded for the person who made them so the history
still reads sensibly. The app removes the shared copy from that phone.

Leaving a care circle stops that account's access and removes the shared
copy from that phone. When the last member leaves, or the organizer
deletes the circle, the active care-circle records and group audit history
are deleted from the active database. Invitation, notification, service,
and provider-backup records may follow their own retention periods.

Individual deletions are propagated as tombstones for sync and may remain
in the server history described above while the care circle exists.
Verified deletion requests sent by email are actioned within 30 days.

## Your Rights

You can see and correct the records available to your role, export the
emergency card as plain text, and delete entries from the app. Exporting
sends a copy to the app or person you choose through the iOS share sheet;
after that, the recipient's privacy policy controls that copy. Deleting an
entry hides it in the app and follows the sync and audit retention rules
above. For anything you cannot do in the app, email the address below.

Elderhub is not currently offered in the European Union or the United
Kingdom.

## Children's Privacy

Elderhub is not directed at children under 13 and does not knowingly
collect their information.

## Changes

Updates to this policy will be posted on this page with a revised date.

## Contact

Privacy questions:
[jackwallner+medlist@gmail.com](mailto:jackwallner+medlist@gmail.com)

[Support](https://jackwallner.com/ios/elderhub/support.html) ·
[Terms of Use](https://jackwallner.com/ios/elderhub/terms.html)

[Home](https://jackwallner.com/ios/elderhub/)
[Consumer Health Data](https://jackwallner.com/ios/elderhub/consumer-health-data.html)
[Terms](https://jackwallner.com/ios/elderhub/terms.html)
[Support](https://jackwallner.com/ios/elderhub/support.html)
