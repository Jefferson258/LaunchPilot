# LaunchPilot intake inbox

# One job per line, format: `product | prompt`.
# Lines starting with `#` are ignored. `pilot dispatch` takes an exclusive lock,
# runs the first unprocessed (uncommented) line, marks it `# running: `, and
# changes it to `# done: ` or `# failed (<exit code>): ` after the pipeline
# returns. Dispatch output is also saved under `jobs/`.
#
# The full pipeline is not retried automatically because it can create commits,
# push branches, or open PRs. After reviewing the dispatch log, retry explicitly:
#
#   ./bin/pilot dispatch --retry-failed
#
# A machine crash can leave a visible `# running: ` record and a stale lock.
# Make sure no pipeline is still active, then recover the lock and job
# explicitly:
#
#   ./bin/pilot dispatch --recover-lock
#   ./bin/pilot dispatch --recover-running
#
# An active dispatcher is never interrupted or unlocked automatically.
#
# Examples (uncomment one after replacing the product key):
#
# example-site | Make the hero background a soft blue and rebuild
# example-site | Add an FAQ section below the pricing table
# example-app | Increase the grid thumbnail corner radius on the main tab

# How the phone reaches this file
#
# Pick whichever you already use:
# - **Cursor mobile / web chat**: tell the agent the prompt directly (no inbox needed).
# - **Notion**: keep cards in your command-center board; the agent reads them
#   via the Notion MCP and appends here.
# - **Working Copy / a-Shell (iOS)** or **SSH (Blink)**: edit this file or run
#   `./bin/pilot run <product> "<prompt>"` directly on the Mac.
