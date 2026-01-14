locals {
  matching_azs = [
    for az in data.aws_availability_zones.available.names :
    az if contains(data.aws_ec2_instance_type_offerings.az.locations, az)
  ]
}