# Point editors at `e -w` so they block until the editor closes.
let veditor = (which e | where type == external)
if not ($veditor | is-empty) {
    $env.VEDITOR = ($veditor | get path | first)
    $env.EDITOR = $"($env.VEDITOR) -w"
    $env.GIT_EDITOR = $env.EDITOR
}