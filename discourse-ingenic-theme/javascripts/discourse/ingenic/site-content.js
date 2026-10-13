import getURL from "discourse/lib/get-url";

const ENDPOINT = "/ingenic/site";

// One request per page load, shared by the two places that draw this content.
// The homepage slots and the footer both mount on the homepage, and without
// this they would ask for the same three short lists a moment apart.
//
// The promise is what is memoised rather than the payload, so two components
// mounting in the same tick share the request in flight instead of the second
// one arriving after the first has finished and asking again.
//
// A failed request resolves to empty lists rather than rejecting: a footer that
// cannot load its links is a footer that is not drawn, which is not a reason to
// break the page it sits on.
let pending = null;

export function loadSiteContent() {
  pending ??= fetch(getURL(ENDPOINT), {
    headers: { Accept: "application/json" },
  })
    .then((response) => (response.ok ? response.json() : {}))
    .catch(() => ({}));

  return pending;
}
