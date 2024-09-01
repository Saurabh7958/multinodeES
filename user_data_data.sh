#!/bin/bash

set -xe

exec > >(tee /var/log/user-data-data.log|logger -t user-data-data) 2>&1

ELASTIC_USER="${ELASTIC_USER}"
ELASTIC_PASSWORD="${ELASTIC_PASSWORD}"
REGION="${REGION}"
INSTANCE_NAME_MASTER="${INSTANCE_NAME_MASTER}"
INSTANCE_NAME_DATA="${INSTANCE_NAME_DATA}"
INSTANCE_NAME_COMMON="${INSTANCE_NAME_COMMON}"
BUCKET_NAME="${BUCKET_NAME}"
CERTS_DIRECTORY="/etc/elasticsearch/certs"

# Update the system and install necessary packages
yum update -y
yum install -y perl-Digest-SHA

# Create certs directory if it doesn't exist
mkdir -p $CERTS_DIRECTORY

wait_for_certificate() {
  while true; do
    if aws s3 ls "s3://$BUCKET_NAME/elastic-certificates.p12" > /dev/null; then
      echo "Certificate found in S3. Downloading..."
      aws s3 cp s3://$BUCKET_NAME/elastic-certificates.p12 $CERTS_DIRECTORY
      chmod 777 $CERTS_DIRECTORY
      break
    else
      echo "Certificate not found in S3. Waiting..."
      sleep 30
    fi
  done
}

# Wait for the certificate to be available before proceeding
wait_for_certificate
# Download and install Elasticsearch
wget https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-7.17.14-aarch64.rpm
wget https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-7.17.14-aarch64.rpm.sha512
shasum -a 512 -c elasticsearch-7.17.14-aarch64.rpm.sha512
rpm --install elasticsearch-7.17.14-aarch64.rpm

# Start and enable Elasticsearch service
systemctl daemon-reload
systemctl enable elasticsearch.service
systemctl start elasticsearch.service

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
if [ -n "$DATA_IPS" ]; then
    # Add Elasticsearch configurations to elasticsearch.yml
    cat <<EOF >> /etc/elasticsearch/elasticsearch.yml
http.port: 9200
network.host: 0.0.0.0
cluster.name: mycluster
xpack.security.enabled: true
xpack.security.transport.ssl.enabled: true
xpack.security.transport.ssl.verification_mode: certificate
xpack.security.transport.ssl.keystore.path: $CERTS_DIRECTORY/elastic-certificates.p12
xpack.security.transport.ssl.truststore.path: $CERTS_DIRECTORY/elastic-certificates.p12
node.roles: [data]
discovery.seed_hosts: [$(echo $MASTER_IPS $DATA_IPS | sed 's/ /", "/g' | sed 's/^/"/' | sed 's/$/"/')]
cluster.initial_master_nodes: [$(echo $MASTER_IPS | sed 's/ /", "/g' | sed 's/^/"/' | sed 's/$/"/')]
EOF

    # Restart Elasticsearch service
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

