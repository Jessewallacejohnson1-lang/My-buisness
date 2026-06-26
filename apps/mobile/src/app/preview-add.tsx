// TEMP preview harness — renders the Add screen unauthenticated for a headless screenshot. Delete after verifying.
import Add from './(tabs)/add'

export default function PreviewAdd() {
  return <Add initialPhase="form" initialKind="event" />
}
