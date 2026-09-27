# How LaunchPilot compares

LaunchPilot is a **multi-product orchestration CLI**: it wraps a Cursor SDK
coding step, then runs deterministic bash for build → visual QA → commit →
push → PR, with **hard gates** before production deploy or TestFlight.

It does **not** replace signing/CI templates, ASC skill packs, or chat-only
upload rules. It sits one layer above those pieces and reuses sibling tooling
(e.g. a local `TestFlight/` kit, Vercel CLI) instead of reimplementing them.

## Quick map

| Project | What it is | Overlap with LaunchPilot | Where LaunchPilot differs |
|---------|------------|--------------------------|---------------------------|
| [indie-app-autopilot](https://github.com/rshankras/indie-app-autopilot) | Agent pipeline: GitHub issue → PR → TestFlight → App Store, with two human gates (merge + submit) | End-to-end ship loop; human gates before public release | LaunchPilot is a **local multi-product CLI** (apps + marketing sites), Cursor-SDK coding + bash steps, product registry in `products.json`. Not issue-queue / specialized agent-role architecture. |
| [apple-shipkit](https://github.com/indiagrams/apple-shipkit) | Release-engineering **template**: signing, GitHub Actions CI, TestFlight, ASC submission | TestFlight / ship path | LaunchPilot does not mint CI certs or ship Fastlane workflows. It **calls** an external TestFlight kit behind `--confirm`. Use shipkit (or similar) *inside* a product repo; LaunchPilot orchestrates across products. |
| [cursor-appstore-upload-rules](https://github.com/EmadBeltaje/cursor-appstore-upload-rules) | Cursor **chat rules** to build IPA + upload / submit from a prompt | “Ask Cursor to upload” | LaunchPilot keeps upload **out of the agent chat** and behind an explicit CLI gate. Coding uses the Cursor SDK; ship steps are deterministic scripts, not paste-your-`.p8`-into-chat rules. |
| [ios-dev-agent](https://github.com/moasq/ios-dev-agent) (moasq) | Large **agent skill** pack for iOS + ASC (`asc` CLI), usable in Cursor and other tools | ASC / TestFlight / build guidance for agents | LaunchPilot is not a skill library. Skills teach an agent *how*; LaunchPilot is a **pipeline runner** with a product registry and policy gates. Complementary, not competing. |

## Positioning (honest)

**LaunchPilot’s niche:** one CLI that knows many local products, runs a Cursor
agent for the code change, then applies the same build/QA/PR path everywhere,
and **stops** before anything that hits production users or Apple’s upload
APIs unless you pass an explicit flag.

**Not claimed today:**

- Full GitHub-issue autopilot with WIP queues and feedback-triage agents
- Ephemeral CI signing / Fastlane Match replacement
- Chat-rule IPA upload from inside the IDE
- A portable skill pack for arbitrary coding agents

Those tools solve adjacent problems well. LaunchPilot’s bet is **orchestration
+ policy across a workspace of products**, with coding delegated to Cursor and
shipping delegated to existing kits — gated by default.
