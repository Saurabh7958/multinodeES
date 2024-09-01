#!/bin/bash

set -xe

exec > >(tee /var/log/user-data-master.log|logger -t user-data-master) 2>&1

ELASTIC_USER="${ELASTIC_USER}"
ELASTIC_PASSWORD="${ELASTIC_PASSWORD}"
REGION="${REGION}"
INSTANCE_NAME_MASTER="${INSTANCE_NAME_MASTER}"
INSTANCE_NAME_DATA="${INSTANCE_NAME_DATA}"
INSTANCE_NAME_COMMON="${INSTANCE_NAME_COMMON}"
BUCKET_NAME="${BUCKET_NAME}"
CERTS_DIRECTORY="/etc/elasticsearch/certs"
CERT_FILE="$CERTS_DIRECTORY/elastic-certificates.p12"
CERT_GENERATED_FLAG="/var/log/cert_generated"

# Update the system and install necessary packages
yum update -y
yum install -y perl-Digest-SHA wget

# Create certs directory if it doesn't exist
mkdir -p $CERTS_DIRECTORY
wget https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-7.17.14-aarch64.rpm
wget https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-7.17.14-aarch64.rpm.sha512
shasum -a 512 -c elasticsearch-7.17.14-aarch64.rpm.sha512
rpm --install elasticsearch-7.17.14-aarch64.rpm

# Start and enable Elasticsearch service
systemctl daemon-reload
systemctl enable elasticsearch.service
systemctl start elasticsearch.service

# Function to wait for the certificate to be available in S3
wait_for_certificate() {
  while true; do
    if aws s3 ls "s3://$BUCKET_NAME/elastic-certificates.p12" > /dev/null; then
      echo "Certificate found in S3. Downloading..."
      aws s3 cp s3://$BUCKET_NAME/elastic-certificates.p12 $CERT_FILE
      chmod 777 $CERT_FILE
      break
    else
      echo "Certificate not found in S3. Waiting..."
      sleep 30
    fi
  done
}

# Function to attempt to acquire the lock for generating the certificate
acquire_lock() {
  LOCK_FILE="/var/log/cert_generation_lock"
  exec 200>$LOCK_FILE
  flock -n 200 && return 0 || return 1
}

# Check if this instance has already generated and uploaded the certificate
if [ ! -f "$CERT_GENERATED_FLAG" ]; then
  # Attempt to acquire the lock to generate the certificate
  if acquire_lock; then
    # Check if the certificate already exists in S3
    if aws s3 ls "s3://$BUCKET_NAME/elastic-certificates.p12" > /dev/null; then
      # If the certificate exists, download it
      wait_for_certificate
    else
      # If the certificate doesn't exist, generate it and upload it to S3
      echo | /usr/share/elasticsearch/bin/elasticsearch-certutil ca --out /etc/elasticsearch/certs/elastic-stack-ca.p12 --silent
      printf "\n" | /usr/share/elasticsearch/bin/elasticsearch-certutil cert --ca /etc/elasticsearch/certs/elastic-stack-ca.p12 --out /etc/elasticsearch/certs/elastic-certificates.p12 --silent --pass ""
      aws s3 cp $CERT_FILE s3://$BUCKET_NAME/elastic-certificates.p12
      chmod 777 $CERT_FILE
      touch $CERT_GENERATED_FLAG  # Mark that this instance has generated the certificate
    fi
  else
    # If another instance is generating the certificate, wait and download it
    wait_for_certificate
  fi
else
  # If this instance has already generated the certificate, download it
  wait_for_certificate
fi

# Retrieve private IP addresses of running instances with the specified tag for master nodes
MASTER_IPS=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${INSTANCE_NAME_MASTER}" "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[?Tags[?Key==`Type` && Value==`Master`]].PrivateIpAddress' \
    --output text \
    --region ${REGION})

# Retrieve private IP addresses of running instances with the specified tag for data nodes
DATA_IPS=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${INSTANCE_NAME_DATA}" "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[?Tags[?Key==`Type` && Value==`Data`]].PrivateIpAddress' \
    --output text \
    --region ${REGION})

# Check if any IP addresses were retrieved
if [ -n "$MASTER_IPS" ]; then
    # Add Elasticsearch configurations to elasticsearch.yml
    cat <<EOF >> /etc/elasticsearch/elasticsearch.yml
http.port: 9200
network.host: 0.0.0.0
cluster.name: mycluster
xpack.security.enabled: true
xpack.security.transport.ssl.enabled: true
xpack.security.transport.ssl.verification_mode: certificate
xpack.security.transport.ssl.keystore.path: $CERT_FILE
xpack.security.transport.ssl.truststore.path: $CERT_FILE
node.roles: [master]
discovery.seed_hosts: [$(echo $MASTER_IPS $DATA_IPS | sed 's/ /", "/g' | sed 's/^/"/' | sed 's/$/"/')]
cluster.initial_master_nodes: [$(echo $MASTER_IPS | sed 's/ /", "/g' | sed 's/^/"/' | sed 's/$/"/')]
EOF

    # Restart Elasticsearch service
    systemctl stop elasticsearch.service
    yes | sudo -u elasticsearch /usr/share/elasticsearch/bin/elasticsearch-node repurpose
    systemctl restart elasticsearch.service

    # Add Elasticsearch users and roles
    /usr/share/elasticsearch/bin/elasticsearch-users useradd "$ELASTIC_USER" -p "$ELASTIC_PASSWORD"
    /usr/share/elasticsearch/bin/elasticsearch-users roles "$ELASTIC_USER" --add superuser
    
    # Remove existing Elasticsearch data directory, recreate it, set ownership and permissions, and restart Elasticsearch
    rm -rf /var/lib/elasticsearch
    mkdir /var/lib/elasticsearch
    chown -R elasticsearch:elasticsearch /var/lib/elasticsearch
    chmod -R 755 /var/lib/elasticsearch
    systemctl restart elasticsearch
    
else
    echo "No running instances found with the specified tag or unable to retrieve private IP addresses for data nodes."
fi

