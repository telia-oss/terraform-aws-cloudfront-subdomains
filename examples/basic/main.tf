provider "aws" {
  region = "eu-west-1"
}

resource "aws_route53_zone" "public" {
  name = "bedrift-dev.telia.io"
}

module "frontend-subdomains" {
  source = "github.com/telia-oss/terraform-aws-cloudfront-subdomains"

  project        = "telia-no-oneportal"
  environment    = "dev"
  hostname       = aws_route53_zone.public.name
  hosted_zone_id = aws_route53_zone.public.zone_id
  default_object = "/index.html"
}
