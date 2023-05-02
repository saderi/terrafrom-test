variable "project" {}
variable "credentials_file" {
    default = "./account.json"
}

variable "region" {
  default = "us-central1"
}

variable "zone" {
  default = "us-central1-a"
}

variable "os_image" {
  default = "debian-cloud/debian-10"
}
