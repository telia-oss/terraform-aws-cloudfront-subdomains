variable "hostname" {
  type = string
  description = "URL of which to create *.branch. subdomains"
}

variable "hosted_zone_id" {
  type = string
  description = "ID of the hosted zone"
}

variable "project" {
  type = string
  description = "Used for names and tags"
}

variable "environment" {
  type = string
  description = "Used for names and tags"
}

variable "default_object" {
  type        = string
  description = "Default object (within branch folder) to be served if requested file does not exist"
}

variable "s3_bucket_name" {
  type = string
  description = "Name of s3 bucket - default is based on project, environment and hostname"
  default = null
}
