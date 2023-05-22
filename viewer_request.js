exports.handler = (event, context, callback) => {
    const request = event.Records[0].cf.request;
    const host = request.headers.host[0].value;

    // AD login callback.
    //
    // Wildcard redirect domains are not supported in AD. Thus,
    // 'branch.${hostname}' is used as redirect url after login for all
    // subdomains, and will further redirect to correct subdomain. The subdomain
    // is sent as 'state' in login, and returned in the 'state' query paramater.
    // https://learn.microsoft.com/en-us/azure/active-directory/develop/reply-url#use-a-state-parameter
    if (host == "branch.${hostname}") {
        // Redirect to subdomain within state parameter (2nd one, delimited by '|').
        // Cannot simply read param in lambda, since request mode is not query:
        // https://learn.microsoft.com/en-us/azure/active-directory/develop/v2-oauth2-auth-code-flow
        const content = `
            <\!DOCTYPE html>
            <html lang="en">
                <body onload="redirect()"></body>
                <script>
                    function redirect() {
                        // Expression for extracting the subdomain from state argument/fragment
                        const re = new RegExp('state=[^&#]+%7c([0-9a-zA-Z-]+)');
                        const results = re.exec(location.href);

                        const currentHost = "https://branch.${hostname}";
                        const targetHost = "https://" + results[1] + ".branch.${hostname}"
                        const newUrl = location.href.replace(currentHost, targetHost);

                        // Redirect to new host (with subdomain from state argument/fragment)
                        window.location.replace(newUrl);
                    }
                </script>
            </html>
            `;

        const response = {
            status: '200',
            statusDescription: 'OK',
            headers: {
                'cache-control': [{
                    key: 'Cache-Control',
                    value: 'max-age=100'
                }],
                'content-type': [{
                    key: 'Content-Type',
                    value: 'text/html'
                }]
            },
            body: content,
        };
        
        return callback(null, response);
    }
    
    // Rewrite the uri to request the default object if asking for '/', or
    // 'cloudfrontindex=true' (file not found in earlier request, see
    // origin-response function).
    const uri = (request.uri === "/" || request.querystring.includes('cloudfrontindex=true'))
        ? "${default_object}"
        : request.uri;

    // Prepend the subdomain of '.branch.${hostname}' to the uri, to
    // target the S3 bucket subfolder corresponding to that subdomain.
    const subdomain = host.split(".branch.${hostname}")[0];
    request.uri = "/" + subdomain + uri;
    
    return callback(null, request);
};
