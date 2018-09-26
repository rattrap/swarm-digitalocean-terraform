# Swarm - DigitalOcean - Terraform

Deploy a Swarm cluster on DigitalOcean using Terraform.

## Requirements

* [DigitalOcean](https://www.digitalocean.com/) account
* DigitalOcean Token [In DO's settings/tokens/new](https://cloud.digitalocean.com/settings/tokens/new)
* [Terraform](https://www.terraform.io/)

### On Mac

With brew installed, all tools can be installed with

```bash
brew install terraform 
```

## Generate private / public keys

```
ssh-keygen -t rsa -b 4096
```

The system will prompt you for a file path to save the key. We recommend you use `./secrets/id_rsa` and "empty" as in no passphrase (password protected keys are not supported by Terraform)

## Add this key to your SSH agent

```bash
eval `ssh-agent -s`
ssh-add ./secrets/id_rsa
```

## Invoke Terraform

We put our DigitalOcean token in the file `./secrets/DO_TOKEN` (this directory is mentioned in `.gitignore`, of course, so we don't leak it)

Then we setup the environment variables (step into `this repository` root).

Run out setup script `./setup.sh`. Invoke it as

```bash
. ./setup.sh
```

Optionally, you can customize the datacenter *region* via:
```bash
export TF_VAR_do_region=fra1
```
The default region is `lon1`. You can find a list of available regions from [DigitalOcean](https://developers.digitalocean.com/documentation/v2/#list-all-regions).

After setup, call `terraform apply`

```bash
terraform apply
```

And you are good to go!