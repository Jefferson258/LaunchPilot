# Corvim — App Store Connect (paste-ready)

**ASC app:** Corvim · `com.corvim.Corvim` · ID `6760210188`  
**Device:** iPhone (+ Apple Watch companion) · screenshots iPhone 6.7"

---

## App Information

| Field | Value |
|-------|--------|
| **Name** | Corvim |
| **Subtitle** (≤30) | Train smarter with motion |
| **Primary category** | Health & Fitness |
| **Secondary category** | Social Networking |
| **Copyright** | © 2026 Broken Watch Software LLC |
| **Support URL** | https://corvim.app |
| **Marketing URL** | https://corvim.app |
| **Privacy Policy URL** | https://corvim.app/privacy |

---

## Promotional text (optional)

Share finished workouts with friends, track quality from your Apple Watch, and build programs coaches can follow—all in one place.

---

## Description

Corvim is a strength and conditioning companion built around real sessions: log sets from your phone or Apple Watch, see motion-informed quality signals where available, and keep a clear history of every workout.

**Workouts**  
Pick from common lifts, run guided sessions, and capture sets with reps, weight, and optional motion metrics when you train with Apple Watch.

**Progress**  
Review past sessions, trends, and summaries so you know what you actually did in the gym—not just what you planned.

**Social**  
Follow friends, see their shared workouts, leave comments, and save workouts you want to try. Report content that breaks community guidelines.

**Groups**  
Train as a team: group feeds, invites, and coaching workflows for athletes and coaches on supported plans.

**Privacy**  
Sign in with Apple. Your account and social data are protected by our backend rules in production.

---

## Keywords (≤100 characters)

```
workout,gym,strength,Apple Watch,training,fitness,social,coach,athlete,reps
```

---

## Screenshot order (iPhone 6.7")

| # | File | ASC caption idea |
|---|------|------------------|
| 1 | `01-home.png` | Your training hub |
| 2 | `02-workout.png` | Log every set |
| 3 | `03-progress.png` | Track your progress |
| 4 | `04-social.png` | Train with friends |
| 5 | `05-groups.png` | Team training |

---

## Notes for Review

```
Corvim is a fitness and workout tracking app for iPhone and Apple Watch.

SIGN-IN: Sign in with Apple is required for social features. Users must accept Terms and Privacy on first launch.

DEMO / TEST: On launch, enable "Dev mode, Fake data + motion for simulator" and "Fake social" switches in Settings if present, OR sign in with Apple using the reviewer's Apple ID.

APPLE WATCH: Optional. Core workout logging works on iPhone without a Watch. Watch provides motion-based rep counting when paired.

HEALTH / WELLNESS: General fitness and wellness only — not medical advice.

ACCOUNT DELETION: Settings → delete account flow (confirm path in build before submit).

UGC: Social feed allows workout posts and comments. Users can report posts.

PRIVACY POLICY: https://corvim.app/privacy
TERMS: https://corvim.app/terms

ENCRYPTION: ITSAppUsesNonExemptEncryption = NO (standard HTTPS only).
```

---

## Pre-submit checklist

- [ ] Account deletion works end-to-end
- [ ] Privacy labels match APP_PRIVACY_QUESTIONNAIRE.md
- [ ] Screenshots match submitted binary (fake social / dev toggles off for production marketing if required)
- [ ] IAP/subscription copy accurate if paywall ships
