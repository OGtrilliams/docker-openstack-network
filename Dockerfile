FROM ubuntu:14.04

MAINTAINER EnnWeb Cloud <cloud@ennweb.com>

ENV \
  DEBIAN_FRONTEND=noninteractive \
  FORCE_INSTALL=no \
  RABBIT_USER=openstack \
  RABBIT_PASS=rabbitpass \
  CONTROLLER_HOST=controller \
  REGION_NAME=RegionOne \
  NEUTRON_PASS=neutronpass \
  METADATA_SECRET=metadatasecret \
  INTERFACE_NAME=eth1 \
  TUNNEL_IP=10.0.0.1 \
  HA_MODE=L3_HA

RUN \
  apt-get update && \
  apt-get install -y software-properties-common && \
  add-apt-repository  -y cloud-archive:liberty && \
  apt-get update && apt-get -y dist-upgrade && \
  apt-get install -y python-pymysql neutron-plugin-ml2 neutron-plugin-openvswitch-agent neutron-l3-agent \
    neutron-dhcp-agent neutron-metadata-agent keepalived && \
  apt-get autoclean && \
  apt-get autoremove && \
  rm -rf /var/lib/apt/lists/*

ADD entrypoint.sh /

ENTRYPOINT ["/entrypoint.sh"]
