exports.handler = (event, context, callback) => {
    const request = event.Records[0].cf.request;
    const response = event.Records[0].cf.response;
    
    if (response.status >= 400 && response.status < 500) {
        // Fallback file (index.html) not found
        if (request.querystring.includes("cloudfrontindex=true")) {
            const content = `
            <\!DOCTYPE html>
            <html lang="en">
                <head>
                    <style>
                        body { width: 35em; margin: 0 auto;
                        font-family: Tahoma, Verdana, Arial, sans-serif; }
                    </style>
                </head>
                <body onload="reload()">
                    <h1>Oh :O The page is not deployed yet!
                    Grab a hot beverage and relax for a bit :)</h1>
                </body>
                <script>
                    function reload() {
                        setTimeout("window.location.reload()", 5000);
                    }
                </script>
            </html>
            `;

            response.status = '200';
            response.statusDescription = 'OK';
            response.body = content;
            response.headers["content-type"] = [{
                key: 'Content-Type',
                value: 'text/html',
            }];
        } else {
            // Remove subfolder from uri, as it is added by viewer-request lambda
            // function and would be added again if not removed.
            const uri = `/${request.uri.split("/").slice(2).join("/")}`;
            // Add 'cloudfrontindex=true' to tell viewer-request lambda to rewrite
            // request to target default object.
            const path = request.querystring != ""
                ? `${uri}?${request.querystring}&cloudfrontindex=true`
                : `${uri}?cloudfrontindex=true`;

            // Modify respose to a redirect.
            response.status = 302;
            response.statusDescription = 'Found';
            response.body = '';
            response.headers.location = [{
                key: 'Location',
                value: path,
            }];
        }
    }
    
    return callback(null, response);
};
