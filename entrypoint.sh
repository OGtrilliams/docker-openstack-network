#!/bin/bash

echo 'Starting network service...'

sed -i "s/^#net.ipv4.ip_forward.*/net.ipv4.ip_forward=1/" /etc/sysctl.conf
sed -i "s/^#net.ipv4.conf.all.rp_filter.*/net.ipv4.conf.all.rp_filter=0/" /etc/sysctl.conf
sed -i "s/^#net.ipv4.conf.default.rp_filter.*/net.ipv4.conf.default.rp_filter=0/" /etc/sysctl.conf
sysctl -p

sed -i "\
  s/^# rpc_backend=rabbit.*/rpc_backend=rabbit/; \
  s/^# rabbit_host = localhost.*/rabbit_host=$CONTROLLER_HOST/; \
  s/^# rabbit_userid = guest.*/rabbit_userid = $RABBIT_USER/; \
  s/^# rabbit_password = guest.*/rabbit_password = $RABBIT_PASS/; \
  s/^# auth_strategy = keystone.*/auth_strategy = keystone/; \
  s/^auth_uri =.*/auth_uri = http:\/\/$CONTROLLER_HOST:5000/; \
  s/^identity_uri =.*/auth_url = http:\/\/$CONTROLLER_HOST:35357/; \
  s/^admin_tenant_name =.*/auth_plugin = password\nproject_domain_id = default\nuser_domain_id = default\nproject_name = service/; \
  s/^admin_user =.*/username = neutron/; \
  s/^admin_password =.*/password = $NEUTRON_PASS/; \
  s/^# service_plugins.*/service_plugins = router/; \
  s/^# allow_overlapping_ips.*/allow_overlapping_ips = True/; \
  s/^# allow_automatic_l3agent_failover.*/allow_automatic_l3agent_failover = True/; \
" /etc/neutron/neutron.conf

if [ $HA_MODE == "DVR" ]; then
  sed -i "s/^# router_distributed.*/router_distributed = True/" /etc/neutron/neutron.conf
fi

if [ $HA_MODE == "L3_HA" ]; then
  sed -i "\
    s/^# router_distributed.*/router_distributed = False/; \
    s/^# l3_ha = False.*/l3_ha = True/; \
    s/^# max_l3_agents_per_router.*/max_l3_agents_per_router = 0/; \
  " /etc/neutron/neutron.conf
fi

ML2_CONF=/etc/neutron/plugins/ml2/ml2_conf.ini

sed -i "\
  s/# type_drivers.*/type_drivers = flat,vxlan/; \
  s/# tenant_network_types.*/tenant_network_types = vxlan/; \
  s/# mechanism_drivers.*/mechanism_drivers = openvswitch,l2population/; \
  s/# extension_drivers.*/extension_drivers = port_security/; \
  s/# flat_networks.*/flat_networks = public/; \
  s/# vni_ranges.*/vni_ranges = 1:1000/; \
  s/# vxlan_group.*/vxlan_group = 239.1.1.1/; \
  s/# enable_security_group.*/enable_security_group = True/; \
  s/# enable_ipset.*/enable_ipset = True/; \
" $ML2_CONF

echo "firewall_driver = neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver" >> $ML2_CONF
echo "" >> $ML2_CONF
echo "[ovs]" >> $ML2_CONF
echo "local_ip = $TUNNEL_IP" >> $ML2_CONF
echo "bridge_mappings = public:br-ex" >> $ML2_CONF
echo "enable_tunneling = True" >> $ML2_CONF
echo "" >> $ML2_CONF
echo "[agent]" >> $ML2_CONF
echo "tunnel_types = vxlan" >> $ML2_CONF
echo "l2population = True" >> $ML2_CONF
echo "arp_responder = True" >> $ML2_CONF

if [ $HA_MODE == "DVR" ]; then
    echo "enable_distributed_routing = True" >> $ML2_CONF
fi
if [ $HA_MODE == "L3_HA" ]; then
    echo "enable_distributed_routing = False" >> $ML2_CONF
fi

sed -i "\
  s/# interface_driver = neutron.agent.linux.interface.OVSInterfaceDriver/interface_driver = neutron.agent.linux.interface.OVSInterfaceDriver/; \
  s/^# use_namespaces.*/use_namespaces = True/; \
  s/# external_network_bridge.*/external_network_bridge = br-ex/; \
  s/^# router_delete_namespaces = False.*/router_delete_namespaces = True/; \
" /etc/neutron/l3_agent.ini

if [ $HA_MODE == "DVR" ]; then
    sed -i "s/^# agent_mode.*/agent_mode = dvr_snat/" /etc/neutron/l3_agent.ini
fi
if [ $HA_MODE == "L3_HA" ]; then
    sed -i "s/^# agent_mode.*/agent_mode = legacy/" /etc/neutron/l3_agent.ini
fi

sed -i "\
  s/# interface_driver = neutron.agent.linux.interface.OVSInterfaceDriver/interface_driver = neutron.agent.linux.interface.OVSInterfaceDriver/; \
  s/# dhcp_driver.*/dhcp_driver = neutron.agent.linux.dhcp.Dnsmasq/; \
  s/# use_namespaces.*/use_namespaces = True/; \
  s/# dhcp_delete_namespaces = False.*/dhcp_delete_namespaces = True/; \
  s/# enable_isolated_metadata.*/enable_isolated_metadata = True/; \
  s/# dnsmasq_config_file.*/dnsmasq_config_file = \/etc\/neutron\/dnsmasq-neutron.conf/; \
" /etc/neutron/dhcp_agent.ini

echo "dhcp-option-force=26,1454" > /etc/neutron/dnsmasq-neutron.conf

sed -i "\
  s/^auth_url.*/auth_url = http:\/\/$CONTROLLER_HOST:5000\/v2.0/; \
  s/^auth_region.*/auth_region = $REGION_NAME/; \
  s/^admin_tenant_name.*/admin_tenant_name = service/; \
  s/^admin_user.*/admin_user = neutron/; \
  s/^admin_password.*/admin_password = $NEUTRON_PASS/; \
  s/^# nova_metadata_ip.*/nova_metadata_ip = $CONTROLLER_HOST/; \
  s/^# metadata_proxy_shared_secret.*/metadata_proxy_shared_secret = $METADATA_SECRET/; \
" /etc/neutron/metadata_agent.ini

modprobe openvswitch
service openvswitch-switch start

ifconfig br-ex
if [ $? != 0 ]; then
  ovs-vsctl add-br br-ex
fi

if [ "$INTERFACE_NAME" ]; then
  ovs-vsctl add-port br-ex $INTERFACE_NAME
fi

service neutron-dhcp-agent restart
service neutron-metadata-agent restart
service neutron-l3-agent restart
service neutron-plugin-openvswitch-agent restart

## Setup complete
echo 'Setup complete!...'

while true
  do sleep 1
done
