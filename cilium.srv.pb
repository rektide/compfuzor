---
- hosts: all
  vars:
    TYPE: k3s-cilium
    INSTANCE: main
    BINS:
      - name: install-cilium
        content: |
          

    ETC_FILES:
      - name: settings.yaml
        format: yaml
        content:
          autoDirectNodeRoutes: true
          #ipMasqAgent.enabled: true
          ipv6.enabled: true
         
          bandwidthManager:
            enabled: true
            bbr: true
          bpf:
            # linux 6.7 required https://isovalent.com/blog/post/cilium-netkit-a-new-container-networking-paradigm-for-the-ai-era/
            datapathMode: netkit
            distributedLRU.enabled: true
            # https://docs.cilium.io/en/latest/operations/performance/tuning/#ebpf-host-routing
            events:
              monitorInterval: "10s"
              default:
                rateLimit: 10000
                burstLimit: 50000
            lbAlgorithmAnnotation: true
            lbExternalClusterIP: true
            lbModeAnnotation: true
            mapDynamicSizeRatio: 0.03
            # https://docs.cilium.io/en/latest/operations/performance/tuning/#ebpf-host-routing
            masquerade: true
            preallocateMaps: true
          # https://docs.cilium.io/en/latest/operations/performance/tuning/#bandwidth-manager
          bpfClockProbe: true
          cluster:
            name: "{{cluster}}"
            id: "{{cluster_id|default(99)}}"
          crdWaitTimeout: 30s
          debug:
            enabled: false
          defaultLBServiceIPAM: nodeipam # lbipam
          # probably not supported on most nic's
          #enableIPv4BIGTCP: true
          #enableIPv6BIGTCP: true
          enableIPv4Masquerade: false
          #enableMasqueradeRouteSource: false
          envoy:
            enabled: true
            log:
              accessLogBufferSize: 16384
              format_json:
            securityContext:
              capabilities:
                keepCapNetBindService: true
                envoy:
                  # https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/#bind-to-privileged-port
                  # - MORE
                  - NET_BIND_SERVICE
          externalEnvoyProxy: false
          hubble:
            eventQueueSize: 4096
            metrics:
              enabled: '{dns,drop,tcp,flow,port-distribution,icmp,httpV2:exemplars=true;labelsContext=source_ip\,source_namespace\,source_workload\,destination_ip\,destination_namespace\,destination_workload\,traffic_direction}'
              enableOpenMetrics: true
            relay:
              enabled: true
            ui:
              enabled: true
          # https://docs.cilium.io/en/latest/network/l2-announcements/
          l2annoucements.enabled: true
          #l2podAnnouncements.interface: 
          # https://docs.cilium.io/en/latest/network/node-ipam/
          gatewayAPI:
            enabled: true
            enableAlpn: true
            hostNetwork:
              enabled: true
          # https://github.com/cilium/cilium/issues/38227
          #hostNetwork.enabled: true
          ipam:
            mode: multi-pool
            operator:
              clusterPoolIPv4PodCIDRList: '["10.x/16]'
              clusterPoolIPv4MaskSize: 16
          ipv4NativeRoutingCIDR:
          ipv6NativeRoutingCIDR:
          k8sServiceHost: 
          k8sServicePort: 
          kubeProxyReplacement: true
          kubeProxyReplacementHealthzBindAddr: '0.0.0.0:10256'
          loadBalancer:
            acceleration: native
            dsrDispatch: opt
            l7:
              backend: envoy
            mode: dsr
          l2NeighDiscovery.enabled: true
          maglev:
            hashSeed: ei9cYZx0ouKp2Ux0
            tableSize: 2039
          nodeIPAM:
            enabled: true
          nodePort:
            #autoProtectPortRange: false
            #directRoutingDevice: eth1
            enabled: true
          prometheus:
            enabled: true
          operator:
            replicas: 1
            prometheus:
              enabled: true
          routingMode: native
          scheduling.mode: kube-scheduler
          #sctp.enabled: true
          socketLB:
            enabled: true # ??
            #hostNamespaceOnly: true
          #devices: ____
    CRDS:
      - https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.3.0/config/crd/standard/gateway.networking.k8s.io_gatewayclasses.yaml
      - https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.3.0/config/crd/standard/gateway.networking.k8s.io_gateways.yaml
      - https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.3.0/config/crd/standard/gateway.networking.k8s.io_httproutes.yaml
      - https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.3.0/config/crd/standard/gateway.networking.k8s.io_referencegrants.yaml
      - https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.3.0/config/crd/standard/gateway.networking.k8s.io_grpcroutes.yaml
      - https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.3.0/config/crd/experimental/gateway.networking.k8s.io_tlsroutes.yaml


