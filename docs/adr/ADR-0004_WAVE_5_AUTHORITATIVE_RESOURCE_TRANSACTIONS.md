# ADR-0004: Wave 5 authoritative resource transactions

Status: implemented for W5.5; owner manual acceptance pending.

W5.4 synchronizes movement and voxels. Extending that model to items requires preserving global quantity and stateful identity while requests may race, retry or lose their results.

HOST is the sole resource authority. Transport binding determines actor. Strict protocol-4 requests carry sequence, transaction ID and expected previous domain revisions/stacks. HOST validates context, range, canonical capability, body-derived aim and output capacity, then routes through existing transactional primitives. Placement prepares item consumption around one voxel/functional-object commit. Shared storage and kiln commands use the same ownership checks as personal inventory. Exact retries return a bounded per-character host-session cache result, including after reconnect; no durable retry journal is introduced.

JOIN maintains read views with canonical inventory/grid/workstation primitives for presentation. It creates no gameplay authority or world save. Both local and remote inventory UIs submit the same commands, display pending state and wait for authoritative facts. Complete validated fragments and domain revision checks isolate corrupt or missing data; resync replaces the current domain. Reliable resource-state channel 6 and command channel 7 preserve movement/voxel channels; drop positions use channel 8 at 10 Hz. Initial readiness uses the complete relevant snapshot digest. Per-stream, assembly, queue and rate bounds fail safely.

Save v4 already represents independent players and resource objects. Disconnect resolves staging where possible and retains it otherwise; save must resolve it or fail. Global instance uniqueness and quantity checks span all authoritative endpoints. Food/water items replicate as resources, while consumption and Rest Mat survival effects remain W5.6. Survival state, remote death/recovery, host migration, relay and later network topologies are outside this decision.

Consequences: stale commands may require the player to retry after updated facts; publication across independent domains can be briefly staggered, but clients never commit resources. Idempotency lasts only for the last 256 results per character within the running HOST. These limits are explicit and covered by the W5.5 verifier.
