// Viewer request on /api/*: the Listings API serves /listings, not /api/listings.
function handler(event) {
  var request = event.request;
  request.uri = request.uri.replace(/^\/api/, "") || "/";
  return request;
}
