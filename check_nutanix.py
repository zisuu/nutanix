#!/usr/bin/python -B

import json
import argparse
import os
import random
import requests
import sys
import traceback
import pprint
from requests.packages.urllib3.exceptions import InsecureRequestWarning
requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

parser = argparse.ArgumentParser()

parser.add_argument("-H", "--host", required=True, type=str, help="Server to connect to")
parser.add_argument("-u", "--user", required=True, type=str, help="username")
parser.add_argument("-p", "--password", required=True, type=str, help="password")
parser.add_argument("-C", "--check", required=True, type=str, help="Defines which check to run")
parser.add_argument("-w", "--warning", type=int, help="Defines warning threshold in percent")
parser.add_argument("-c", "--critical", type=int, help="Defines critical threshold in percent")



args = parser.parse_args()

if args.host:
    host = args.host

if args.user:
    user = args.user

if args.password:
    password = args.password

if args.check:
        check = args.check

if args.warning:
        warning = args.warning

if args.critical:
        critical = args.critical




# Connect to API
# ------------------


class TestRestApi():
  def __init__(self):

    self.serverIpAddress = host
    self.username = user
    self.password = password
    BASE_URL = 'https://%s:9440/PrismGateway/services/rest/v2.0/'
    self.base_url = BASE_URL % self.serverIpAddress
    self.session = self.get_server_session(self.username, self.password)


  def get_server_session(self, username, password):

    session = requests.Session()
    session.auth = (username, password)
    session.verify = False
    session.headers.update(
        {'Content-Type': 'application/json; charset=utf-8'})
    return session

  def get_cluster_information(self):

    clusterInfoURL = self.base_url + "/cluster"
    serverResponse = self.session.get(clusterInfoURL)
    return serverResponse.status_code, json.loads(serverResponse.text)

  def get_fault_tolerance_node(self):

    faultToleranceNodeURL = self.base_url + "/cluster/domain_fault_tolerance_status/NODE"
    serverResponse = self.session.get(faultToleranceNodeURL)
    return serverResponse.status_code, json.loads(serverResponse.text)

  def get_fault_tolerance_disk(self):

    faultToleranceDiskURL = self.base_url + "/cluster/domain_fault_tolerance_status/DISK"
    serverResponse = self.session.get(faultToleranceDiskURL)
    return serverResponse.status_code, json.loads(serverResponse.text)

  def get_fault_tolerance_rackable_unit(self):

    faultToleranceRackableUnitURL = self.base_url + "/cluster/domain_fault_tolerance_status/RACKABLE_UNIT"
    serverResponse = self.session.get(faultToleranceRackableUnitURL)
    return serverResponse.status_code, json.loads(serverResponse.text)

  def get_ha_state(self):

    clusterhastateURL = self.base_url + "/ha"
    serverResponse = self.session.get(clusterhastateURL)
    return serverResponse.status_code, json.loads(serverResponse.text)

  def get_alert_state(self):

    clusteralertURL = self.base_url + "/alerts/?acknowledged=false&severity=critical"
    serverResponse = self.session.get(clusteralertURL)
    return serverResponse.status_code, json.loads(serverResponse.text)

  def get_unprotecded_vms(self):

    unprotectedURL = self.base_url + "/protection_domains/unprotected_vms"
    serverResponse = self.session.get(unprotectedURL)
    return serverResponse.status_code, json.loads(serverResponse.text)

  def get_virtualdisks(self):

    virtualdisksURL = self.base_url + "/virtual_disks"
    serverResponse = self.session.get(virtualdisksURL)
    return serverResponse.status_code, json.loads(serverResponse.text)


################# GET CLUSTER INFO #################

#if check == "clusterinfo":
#  try:

#    testRestApi = TestRestApi()
#    status, clusterinfo = testRestApi.get_cluster_information()

#    pp = pprint.PrettyPrinter(indent=2)
#    pp.pprint(clusterinfo)
#    exit(0)

#  except Exception as ex:
#    print (ex)
#    exit(1)


################# HA CHECKS #################

if check == "hastate":
  try:

    testRestApi = TestRestApi()
    status, ha = testRestApi.get_ha_state()

    status_message_strings = []

    status_code = 1

    if ha.get('failover_enabled') == True:
        status_message_strings.append("OK: Failover enabled %s" % ha.get('failover_enabled'))
        status_code = 0
    else:
        status_message_strings.append("CRITICAL: Failover enabled %s" % ha.get('failover_enabled'))
        status_code = 2

    if ha.get('num_host_failures_to_tolerate') == 1:
        status_message_strings.append("OK: Number of failures to tolerate %s" % ha.get('num_host_failures_to_tolerate'))
    else:
        status_message_strings.append("CRITICAL: Number of failures to tolerate %s" % ha.get('num_host_failures_to_tolerate'))
        status_code = 2

    if ha.get('failover_in_progress_host_uuids') == None:
        status_message_strings.append("OK: Failover in progress host_uuids %s" % ha.get('failover_in_progress_host_uuids'))
    else:
        status_message_strings.append("CRITICAL: Failover in progress host_uuids %s" % ha.get('failover_in_progress_host_uuids'))
        status_code = 2

    if ha.get('ha_state') == "HighlyAvailable":
        status_message_strings.append("OK: HA state %s" % ha.get('ha_state'))
    else:
        status_message_strings.append("CRITICAL: HA state %s" % ha.get('ha_state'))
        status_code = 2

    print(status_message_strings)
    exit(status_code)


  except Exception as ex:
    print (ex)
    exit (1)


################# CLUSTER FAULT TOLERANCE STATUS NODE #################

if check == "getFaultToleranceStatusNode":
  try:

    testRestApi = TestRestApi()
    status, faultToleranceNode = testRestApi.get_fault_tolerance_node()

    status_message_strings = []

    status_code = 1

    # check node fault tolerance
    ## STATIC_CONFIGURATION
    if faultToleranceNode.get('component_fault_tolerance_status').get('STATIC_CONFIGURATION').get('number_of_failures_tolerable') == 1:
        status_message_strings.append("OK: STATIC_CONFIGURATION: 1")
        status_code = 0
    else:
        status_message_strings.append("CRITICAL: STATIC_CONFIGURATION: enabled %s" % faultToleranceNode.get('component_fault_tolerance_status').get('STATIC_CONFIGURATION'))
        status_code = 2

    ## STARGATE_HEALTH
    if faultToleranceNode.get('component_fault_tolerance_status').get('STARGATE_HEALTH').get('number_of_failures_tolerable') == 1:
        status_message_strings.append("OK: STARGATE_HEALTH: 1")
    else:
        status_message_strings.append("CRITICAL: STARGATE_HEALTH: enabled %s" % faultToleranceNode.get('component_fault_tolerance_status').get('STARGATE_HEALTH'))
        status_code = 2

    ## OPLOG
    if faultToleranceNode.get('component_fault_tolerance_status').get('OPLOG').get('number_of_failures_tolerable') == 1:
        status_message_strings.append("OK: OPLOG: 1")
    else:
        status_message_strings.append("CRITICAL: OPLOG: enabled %s" % faultToleranceNode.get('component_fault_tolerance_status').get('OPLOG'))
        status_code = 2

    ## ZOOKEEPER
    if faultToleranceNode.get('component_fault_tolerance_status').get('ZOOKEEPER').get('number_of_failures_tolerable') == 1:
        status_message_strings.append("OK: ZOOKEEPER: 1")
    else:
        status_message_strings.append("CRITICAL: ZOOKEEPER: enabled %s" % faultToleranceNode.get('component_fault_tolerance_status').get('ZOOKEEPER'))
        status_code = 2

    ## METADATA
    if faultToleranceNode.get('component_fault_tolerance_status').get('METADATA').get('number_of_failures_tolerable') == 1:
        status_message_strings.append("OK: METADATA: 1")
    else:
        status_message_strings.append("CRITICAL: METADATA: enabled %s" % faultToleranceNode.get('component_fault_tolerance_status').get('METADATA'))
        status_code = 2

    ## ERASURE_CODE_STRIP_SIZE
    if faultToleranceNode.get('component_fault_tolerance_status').get('ERASURE_CODE_STRIP_SIZE').get('number_of_failures_tolerable') == 1:
        status_message_strings.append("OK: ERASURE_CODE_STRIP_SIZE: 1")
    else:
        status_message_strings.append("CRITICAL: ERASURE_CODE_STRIP_SIZE: enabled %s" % faultToleranceNode.get('component_fault_tolerance_status').get('ERASURE_CODE_STRIP_SIZE'))
        status_code = 2

    ## EXTENT_GROUPS
    if faultToleranceNode.get('component_fault_tolerance_status').get('EXTENT_GROUPS').get('number_of_failures_tolerable') == 1:
        status_message_strings.append("OK: EXTENT_GROUPS: 1")
    else:
        status_message_strings.append("CRITICAL: EXTENT_GROUPS: enabled %s" % faultToleranceNode.get('component_fault_tolerance_status').get('EXTENT_GROUPS'))
        status_code = 2

    ## FREE_SPACE
    if faultToleranceNode.get('component_fault_tolerance_status').get('FREE_SPACE').get('number_of_failures_tolerable') == 1:
        status_message_strings.append("OK: FREE_SPACE: 1")
    else:
        status_message_strings.append("CRITICAL: FREE_SPACE: enabled %s" % faultToleranceNode.get('component_fault_tolerance_status').get('FREE_SPACE'))
        status_code = 2

    print "FAILURES TOLERABLE: %s" % status_message_strings
    exit(status_code)

  except Exception as ex:
    print (ex)
    exit (1)

################# CLUSTER FAULT TOLERANCE STATUS DISK #################

if check == "getFaultToleranceStatusDisk":
  try:

    testRestApi = TestRestApi()
    status, faultToleranceDisk = testRestApi.get_fault_tolerance_disk()

    status_message_strings = []

    status_code = 1

    # check disk fault tolerance
    ## OPLOG
    if faultToleranceDisk.get('component_fault_tolerance_status').get('OPLOG').get('number_of_failures_tolerable') == 1:
        status_message_strings.append("OK: OPLOG: 1")
        status_code = 0
    else:
        status_message_strings.append("CRITICAL: OPLOG: enabled %s" % faultToleranceDisk.get('component_fault_tolerance_status').get('OPLOG'))
        status_code = 2

    ## METADATA
    if faultToleranceDisk.get('component_fault_tolerance_status').get('METADATA').get('number_of_failures_tolerable') == 1:
        status_message_strings.append("OK: METADATA: 1")
    else:
        status_message_strings.append("CRITICAL: METADATA: enabled %s" % faultToleranceDisk.get('component_fault_tolerance_status').get('METADATA'))
        status_code = 2

    ## ERASURE_CODE_STRIP_SIZE
    if faultToleranceDisk.get('component_fault_tolerance_status').get('ERASURE_CODE_STRIP_SIZE').get('number_of_failures_tolerable') == 1:
        status_message_strings.append("OK: ERASURE_CODE_STRIP_SIZE: 1")
    else:
        status_message_strings.append("CRITICAL: ERASURE_CODE_STRIP_SIZE: enabled %s" % faultToleranceDisk.get('component_fault_tolerance_status').get('ERASURE_CODE_STRIP_SIZE'))
        status_code = 2

    ## EXTENT_GROUPS
    if faultToleranceDisk.get('component_fault_tolerance_status').get('EXTENT_GROUPS').get('number_of_failures_tolerable') == 1:
        status_message_strings.append("OK: EXTENT_GROUPS: 1")
    else:
        status_message_strings.append("CRITICAL: EXTENT_GROUPS: enabled %s" % faultToleranceDisk.get('component_fault_tolerance_status').get('EXTENT_GROUPS'))
        status_code = 2

    ## FREE_SPACE
    if faultToleranceDisk.get('component_fault_tolerance_status').get('FREE_SPACE').get('number_of_failures_tolerable') == 1:
        status_message_strings.append("OK: FREE_SPACE: 1")
    else:
        status_message_strings.append("CRITICAL: FREE_SPACE: enabled %s" % faultToleranceDisk.get('component_fault_tolerance_status').get('FREE_SPACE'))
        status_code = 2

    print "FAILURES TOLERABLE: %s" % status_message_strings
    exit(status_code)


  except Exception as ex:
    print (ex)
    exit (1)

################# CLUSTER FAULT TOLERANCE STATUS RACKABLE_UNIT #################

if check == "getFaultToleranceStatusRackableUnit":
  try:

    testRestApi = TestRestApi()
    status, faultToleranceRackableUnit = testRestApi.get_fault_tolerance_rackable_unit()

    status_message_strings = []

    status_code = 1

    # check block (rackable unit) fault tolerance
    ## STATIC CONFIGURATION
    if faultToleranceRackableUnit.get('component_fault_tolerance_status').get('STATIC_CONFIGURATION').get('number_of_failures_tolerable') == 1:
        status_message_strings.append("OK: STATIC_CONFIGURATION: 1")
        status_code = 0
    else:
        status_message_strings.append("CRITICAL: STATIC_CONFIGURATION: enabled %s" % faultToleranceRackableUnit.get('component_fault_tolerance_status').get('STATIC_CONFIGURATION'))
        status_code = 2

    ## EXTENT_GROUPS
    if faultToleranceRackableUnit.get('component_fault_tolerance_status').get('EXTENT_GROUPS').get('number_of_failures_tolerable') == 1:
        status_message_strings.append("OK: EXTENT_GROUPS: 1")
    else:
        status_message_strings.append("CRITICAL: EXTENT_GROUPS: enabled %s" % faultToleranceRackableUnit.get('component_fault_tolerance_status').get('EXTENT_GROUPS'))
        status_code = 2

    ## ERASURE_CODE_STRIP_SIZE
    if faultToleranceRackableUnit.get('component_fault_tolerance_status').get('ERASURE_CODE_STRIP_SIZE').get('number_of_failures_tolerable') == 1:
        status_message_strings.append("OK: ERASURE_CODE_STRIP_SIZE: 1")
    else:
        status_message_strings.append("CRITICAL: ERASURE_CODE_STRIP_SIZE: enabled %s" % faultToleranceRackableUnit.get('component_fault_tolerance_status').get('ERASURE_CODE_STRIP_SIZE'))
        status_code = 2

    ## OPLOG
    if faultToleranceRackableUnit.get('component_fault_tolerance_status').get('OPLOG').get('number_of_failures_tolerable') == 1:
        status_message_strings.append("OK: OPLOG: 1")
    else:
        status_message_strings.append("CRITICAL: OPLOG: enabled %s" % faultToleranceRackableUnit.get('component_fault_tolerance_status').get('OPLOG'))
        status_code = 2

    ## STARGATE_HEALTH
    if faultToleranceRackableUnit.get('component_fault_tolerance_status').get('STARGATE_HEALTH').get('number_of_failures_tolerable') == 1:
        status_message_strings.append("OK: STARGATE_HEALTH: 1")
    else:
        status_message_strings.append("CRITICAL: STARGATE_HEALTH: enabled %s" % faultToleranceRackableUnit.get('component_fault_tolerance_status').get('STARGATE_HEALTH'))
        status_code = 2

    ## ZOOKEEPER
    if faultToleranceRackableUnit.get('component_fault_tolerance_status').get('ZOOKEEPER').get('number_of_failures_tolerable') == 1:
        status_message_strings.append("OK: ZOOKEEPER: 1")
    else:
        status_message_strings.append("CRITICAL: ZOOKEEPER: enabled %s" % faultToleranceRackableUnit.get('component_fault_tolerance_status').get('ZOOKEEPER'))
        status_code = 2

    ## METADATA
    if faultToleranceRackableUnit.get('component_fault_tolerance_status').get('METADATA').get('number_of_failures_tolerable') == 1:
        status_message_strings.append("OK: METADATA: 1")
    else:
        status_message_strings.append("CRITICAL: METADATA: enabled %s" % faultToleranceRackableUnit.get('component_fault_tolerance_status').get('METADATA'))
        status_code = 2

    ## FREE_SPACE
    if faultToleranceRackableUnit.get('component_fault_tolerance_status').get('FREE_SPACE').get('number_of_failures_tolerable') == 1:
        status_message_strings.append("OK: FREE_SPACE: 1")
    else:
        status_message_strings.append("CRITICAL: FREE_SPACE: enabled %s" % faultToleranceRackableUnit.get('component_fault_tolerance_status').get('FREE_SPACE'))
        status_code = 2

    print "FAILURES TOLERABLE: %s" % status_message_strings
    exit(status_code)


  except Exception as ex:
    print (ex)
    exit (1)


################# ALERT CHECKS #################

if check == "getalerts":
  try:

    testRestApi = TestRestApi()
    status, alert = testRestApi.get_alert_state()

    if alert.get('metadata').get('total_entities') == 0:
        print "OK: %s active critical alerts" % alert.get('metadata').get('total_entities')
        exit (0)
    else:
        print "CRITICAL: %s active critical alerts" % alert.get('metadata').get('total_entities')
        exit (2)

  except Exception as ex:
    print (ex)
    exit (1)


################# RF CHECKS #################

if check == "rfstate":
  try:

    testRestApi = TestRestApi()
    status, clusterinfo = testRestApi.get_cluster_information()

    if clusterinfo.get('cluster_redundancy_state').get('current_redundancy_factor') == clusterinfo.get('cluster_redundancy_state').get('desired_redundancy_factor'):
        print "OK: desired redundancy factor met"
        exit (0)
    else:
        print "CRITICAL: desired redundancy factor not met"
        exit (2)


  except Exception as ex:
    print (ex)
    exit (1)


################# Memory usage #################

if check == "memoryusage":
  try:

    testRestApi = TestRestApi()
    status, clusterinfo = testRestApi.get_cluster_information()

    usedmemory_in_percent = int(clusterinfo.get('stats').get('hypervisor_memory_usage_ppm')) / 10000

    if usedmemory_in_percent > warning:
        if usedmemory_in_percent > critical:
                print "CRITICAL: memory usage %s%%" % usedmemory_in_percent
                exit (2)
        else:
                print "WARNING: memory usage %s%%" % usedmemory_in_percent
                exit (1)
    else:
        print "OK: memory usage %s%%" % usedmemory_in_percent
        exit (0)

  except Exception as ex:
    print (ex)
    exit (1)


################# CPU usage #################

if check == "cpuusage":
  try:

    testRestApi = TestRestApi()
    status, clusterinfo = testRestApi.get_cluster_information()

    usedcpu_in_percent = int(clusterinfo.get('stats').get('hypervisor_cpu_usage_ppm')) / 10000

    if usedcpu_in_percent > warning:
        if usedcpu_in_percent > critical:
                print "CRITICAL: CPU usage %s%%" % usedcpu_in_percent
                exit (2)
        else:
                print "WARNING: CPU usage %s%%" % usedcpu_in_percent
                exit (1)
    else:
        print "OK: CPU usage %s%%" % usedcpu_in_percent
        exit (0)

  except Exception as ex:
    print (ex)
    exit (1)


################# Storage usage #################

if check == "storageusage":
  try:

    testRestApi = TestRestApi()
    status, clusterinfo = testRestApi.get_cluster_information()

    storageused_in_bytes = (clusterinfo.get('usage_stats').get('storage.usage_bytes'))
    storageused_in_terrabytes = float(storageused_in_bytes)/1024/1024/1024/1024
    storagcapacity_in_bytes = (clusterinfo.get('usage_stats').get('storage.capacity_bytes'))
    storagcapacity_in_terrabytes = float(storagcapacity_in_bytes)/1024/1024/1024/1024
    storageused_in_percent = (float(storageused_in_bytes) / float(storagcapacity_in_bytes))*100

    if storageused_in_percent > warning:
        if storageused_in_percent > critical:
                print "CRITICAL: storage usage %.0f%%, %.2f TiB of %.2f TiB are used" % (storageused_in_percent, storageused_in_terrabytes, storagcapacity_in_terrabytes)
                exit (2)
        else:
                print "WARNING: storage usage %.0f%%, %.2f TiB of %.2f TiB are used" % (storageused_in_percent, storageused_in_terrabytes, storagcapacity_in_terrabytes)
                exit (1)
    else:
        print "OK: storage usage %.0f%%, %.2f TiB of %.2f TiB are used" % (storageused_in_percent, storageused_in_terrabytes, storagcapacity_in_terrabytes)
        exit (0)


  except Exception as ex:
    print (ex)
    exit (1)


################# averageIOPS #################

if check == "avgIOPS":
  try:

    testRestApi = TestRestApi()
    status, clusterinfo = testRestApi.get_cluster_information()

    avgIOPS = int(clusterinfo.get('stats').get('controller_num_iops'))

    if avgIOPS > warning:
        if avgIOPS > critical:
            print "CRITICAL: avg IOPS %s" % avgIOPS
            exit (2)
        else:
            print "WARNING: avg IOPS %s" % avgIOPS
            exit (1)
    else:
        print "OK: avg IOPS %s" % avgIOPS
        exit (0)


  except Exception as ex:
    print (ex)
    exit (1)

################# averageLatency #################

if check == "avgIOLatency":
  try:

    testRestApi = TestRestApi()
    status, clusterinfo = testRestApi.get_cluster_information()

    avgIOLatency = int(clusterinfo.get('stats').get('controller_avg_io_latency_usecs'))

    if avgIOLatency > warning:
        if avgIOLatency > critical:
            print "CRITICAL: avg IO latency %s" % avgIOLatency
            exit (2)
        else:
            print "WARNING: avg IO latency %s" % avgIOLatency
            exit (1)
    else:
        print "OK: avg IO latency %s" % avgIOLatency
        exit (0)


  except Exception as ex:
    print (ex)
    exit (1)

################# unprotecded vms #################

if check == "getUnprotectedVMs":
  try:

    testRestApi = TestRestApi()
    status, unprotecded_vms = testRestApi.get_unprotecded_vms()

    num_of_unprotected_vms = int(unprotecded_vms.get('metadata').get('grand_total_entities'))

    if num_of_unprotected_vms == 0:
        print "OK: all VMs are DR protecded"
        exit (0)
    else:
        print "WARNING: %s unprotecded VMs:" % num_of_unprotected_vms

        # get all unprotected vms
        unprotected_hosts = unprotecded_vms.get('entities')

        # print all vm names of unprotected vms
        for host in unprotected_hosts:
            print host["vm_name"]
        exit (1)


  except Exception as ex:
    print (ex)
    exit (1)
