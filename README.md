# Terraform Module for Cloudfront Subdomains

[![latest release](https://img.shields.io/github/v/release/telia-oss/terraform-aws-cloudfront-subdomains?style=flat-square)](https://github.com/telia-oss/terraform-aws-cloudfront-subdomains/releases/latest)
[![build status](https://img.shields.io/github/actions/workflow/status/telia-oss/terraform-aws-cloudfront-subdomains/main.yml?branch=master&logo=github&style=flat-square)](https://github.com/telia-oss/terraform-aws-cloudfront-subdomains/actions/workflows/main.yml)

Terraform module which creates a Cloudfront resource in AWS, which dynamically
maps subdomains to static files in subfolders of a  S3 bucket.

## Usage

See the [example](examples/basic/README.md).

## Example request flow

```mermaid
sequenceDiagram
    participant AD
    participant User
    participant ViewerRequest
    participant CloudFront
    participant OriginResponse
    participant S3
    User->>ViewerRequest: red-color.branch.<hostname>/auth:ad
    Note over ViewerRequest: Rewrite path (subfolder)
    ViewerRequest->>CloudFront: red-color.branch.<hostname>/red-color/auth:ad
    CloudFront->>S3: telia-no-oneportal-frontend-dev-branch.s3.eu-west-1.amazonaws.com/red-color/auth:ad
    S3->>OriginResponse: File Not Found
    Note over OriginResponse: Rewrite to redirect
    OriginResponse->>User: Redirect red-color.branch.<hostname>/auth:ad?cloudfrontindex=true
    User->>ViewerRequest: red-color.branch.<hostname>/auth:ad?cloudfrontindex=true
    Note over ViewerRequest: Rewrite path (subfolder and file)
    ViewerRequest->>CloudFront: red-color.branch.<hostname>/red-color/shell/index.html
    CloudFront->>S3: telia-no-oneportal-frontend-dev-branch.s3.eu-west-1.amazonaws.com/red-color/shell/index.html
    S3->>OriginResponse: File red-color/shell/index.html
    OriginResponse->>User: File red-color/shell/index.html
    Note over User: Fetches and runs JavaScript files linked in index.html
    User->>AD: /login?state=red-color
    AD->>User: Redirect branch.<hostname>/_callback/internal#35;state=ey...|red-color
    User->>ViewerRequest: branch.<hostname>/_callback/internal#35;state=ey...|red-color
    ViewerRequest->>User: AD redirect script
    Note over User: Rewrite host and redirect
    User->>ViewerRequest: red-color.branch.<hostname>/_callback/internal
    Note over ViewerRequest: Rewrite subfolder
    ViewerRequest->>CloudFront: red-color.branch.<hostname>/red-color/_callback/internal
    CloudFront->>S3: telia-no-oneportal-frontend-dev-branch.s3.eu-west-1.amazonaws.com/red-color/_callback/internal
    S3->>OriginResponse: File Not Found
    Note over OriginResponse: Rewrite to redirect
    OriginResponse->>User: Redirect red-color.branch.<hostname>/_callback/internal?cloudfrontindex=true
    Note over ViewerRequest: Rewrite subfolder and path
    ViewerRequest->>CloudFront: red-color.branch.<hostname>/red-color/shell/index.html
    CloudFront->>S3: telia-no-oneportal-frontend-dev-branch.s3.eu-west-1.amazonaws.com/red-color/shell/index.html
    S3->>OriginResponse: File red-color/shell/index.html
    OriginResponse->>User: File red-color/shell/index.html
```

## Authors

Currently maintained by [these contributors](../../graphs/contributors).

## License

MIT License. See [LICENSE](LICENSE) for full details.
