# Specify the provider (GCP, AWS, Azure)
provider "google" {
  credentials = "${file("access.json")}"
  project = "wlsiowproject-220315"
  region = "asia-southeast1"
}