load("@rules_cc//cc:cc_library.bzl", "cc_library")

# libdatachannel v0.22.5 for the iOS app, the same version Android builds (BG-Media's
# cmake/FindOrFetchLibDataChannel.cmake). Pins and what was taken: third-party/libdatachannel/README.md.
#
# Source lists come from the Linux build graph of v0.22.5 (`ninja -t commands`), so every file here
# is one that build compiles. Exceptions, each decided in README.md:
#   - libsrtp is not built from deps/libsrtp: the app already links WebRTC's copy
#     (//third-party/webrtc/libsrtp:srtp_public), and two copies would clash on srtp_* symbols.
#   - BoringSSL stands in for OpenSSL (//third-party/boringssl), as TDLib already does in this repo.
#   - Namespace rtc is renamed to bgrtc (copt rtc=bgrtc): WebRTC uses rtc:: too (rtc_base), and an
#     ODR clash between the two would be silent. Consumers get the define through `defines`.

cc_library(
    name = "plog",
    hdrs = glob(["plog/include/**/*.h"]),
    includes = ["plog/include"],
    visibility = ["//visibility:private"],
)

# libjuice v1.5.9, ICE/STUN. Crypto is its own picohash (USE_NETTLE=0), so it needs no TLS library.
cc_library(
    name = "libjuice",
    srcs = [
        "libjuice/src/addr.c",
        "libjuice/src/agent.c",
        "libjuice/src/crc32.c",
        "libjuice/src/const_time.c",
        "libjuice/src/conn.c",
        "libjuice/src/conn_poll.c",
        "libjuice/src/conn_thread.c",
        "libjuice/src/conn_mux.c",
        "libjuice/src/base64.c",
        "libjuice/src/hash.c",
        "libjuice/src/hmac.c",
        "libjuice/src/ice.c",
        "libjuice/src/juice.c",
        "libjuice/src/log.c",
        "libjuice/src/random.c",
        "libjuice/src/server.c",
        "libjuice/src/stun.c",
        "libjuice/src/timestamp.c",
        "libjuice/src/turn.c",
        "libjuice/src/udp.c",
    ],
    hdrs = glob([
        "libjuice/include/**/*.h",
        "libjuice/src/*.h",
    ]),
    includes = [
        "libjuice/include",
        "libjuice/include/juice",
        "libjuice/src",
    ],
    defines = ["JUICE_STATIC"],
    local_defines = [
        "JUICE_EXPORTS",
        "USE_NETTLE=0",
    ],
    copts = ["-std=gnu11"],
    visibility = ["//visibility:private"],
)

# usrsctp (ebb18ad), SCTP for data channels. Defines are the Linux build's minus the Linux-only
# HAVE_LINUX_* headers, _GNU_SOURCE and SCTP_DEBUG (a Debug-only option); usrsctp picks its Darwin
# code from the compiler's __APPLE__, so no OS define is needed.
cc_library(
    name = "usrsctp",
    srcs = [
        "usrsctp/usrsctplib/netinet/sctp_asconf.c",
        "usrsctp/usrsctplib/netinet/sctp_auth.c",
        "usrsctp/usrsctplib/netinet/sctp_bsd_addr.c",
        "usrsctp/usrsctplib/netinet/sctp_callout.c",
        "usrsctp/usrsctplib/netinet/sctp_cc_functions.c",
        "usrsctp/usrsctplib/netinet/sctp_crc32.c",
        "usrsctp/usrsctplib/netinet/sctp_indata.c",
        "usrsctp/usrsctplib/netinet/sctp_input.c",
        "usrsctp/usrsctplib/netinet/sctp_output.c",
        "usrsctp/usrsctplib/netinet/sctp_pcb.c",
        "usrsctp/usrsctplib/netinet/sctp_peeloff.c",
        "usrsctp/usrsctplib/netinet/sctp_sha1.c",
        "usrsctp/usrsctplib/netinet/sctp_ss_functions.c",
        "usrsctp/usrsctplib/netinet/sctp_sysctl.c",
        "usrsctp/usrsctplib/netinet/sctp_timer.c",
        "usrsctp/usrsctplib/netinet/sctp_userspace.c",
        "usrsctp/usrsctplib/netinet/sctp_usrreq.c",
        "usrsctp/usrsctplib/netinet/sctputil.c",
        "usrsctp/usrsctplib/netinet6/sctp6_usrreq.c",
        "usrsctp/usrsctplib/user_environment.c",
        "usrsctp/usrsctplib/user_mbuf.c",
        "usrsctp/usrsctplib/user_recv_thread.c",
        "usrsctp/usrsctplib/user_socket.c",
    ],
    hdrs = glob(["usrsctp/usrsctplib/**/*.h"]),
    includes = ["usrsctp/usrsctplib"],
    local_defines = [
        "__Userspace__",
        "SCTP_PROCESS_LEVEL_LOCKS",
        "SCTP_SIMPLE_ALLOCATOR",
        "HAVE_NET_ROUTE_H",
        "HAVE_NETINET_IP_ICMP_H",
        "HAVE_STDATOMIC_H",
        "HAVE_SYS_QUEUE_H",
    ],
    copts = [
        "-std=gnu99",
        "-Wno-unused-function",
        "-Wno-unused-parameter",
    ],
    visibility = ["//visibility:private"],
)

# libdatachannel itself. Flags mirror the Linux build (RTC_ENABLE_MEDIA=1, RTC_ENABLE_WEBSOCKET=0,
# RTC_SYSTEM_JUICE=0, RTC_SYSTEM_SRTP=0, USE_GNUTLS=0, USE_NICE=0). RTC_ENABLE_* and RTC_STATIC are
# also needed by consumers (they change the public headers), so they go in `defines`.
cc_library(
    name = "libdatachannel",
    srcs = [
        "src/candidate.cpp",
        "src/channel.cpp",
        "src/configuration.cpp",
        "src/datachannel.cpp",
        "src/description.cpp",
        "src/mediahandler.cpp",
        "src/global.cpp",
        "src/message.cpp",
        "src/peerconnection.cpp",
        "src/rtcpreceivingsession.cpp",
        "src/track.cpp",
        "src/websocket.cpp",
        "src/websocketserver.cpp",
        "src/rtppacketizationconfig.cpp",
        "src/rtcpsrreporter.cpp",
        "src/rtppacketizer.cpp",
        "src/rtpdepacketizer.cpp",
        "src/h264rtppacketizer.cpp",
        "src/h264rtpdepacketizer.cpp",
        "src/nalunit.cpp",
        "src/h265rtppacketizer.cpp",
        "src/h265nalunit.cpp",
        "src/av1rtppacketizer.cpp",
        "src/rtcpnackresponder.cpp",
        "src/rtp.cpp",
        "src/capi.cpp",
        "src/plihandler.cpp",
        "src/pacinghandler.cpp",
        "src/rembhandler.cpp",
        "src/impl/certificate.cpp",
        "src/impl/channel.cpp",
        "src/impl/datachannel.cpp",
        "src/impl/dtlssrtptransport.cpp",
        "src/impl/dtlstransport.cpp",
        "src/impl/icetransport.cpp",
        "src/impl/init.cpp",
        "src/impl/peerconnection.cpp",
        "src/impl/logcounter.cpp",
        "src/impl/sctptransport.cpp",
        "src/impl/threadpool.cpp",
        "src/impl/tls.cpp",
        "src/impl/track.cpp",
        "src/impl/utils.cpp",
        "src/impl/processor.cpp",
        "src/impl/sha.cpp",
        "src/impl/pollinterrupter.cpp",
        "src/impl/pollservice.cpp",
        "src/impl/http.cpp",
        "src/impl/httpproxytransport.cpp",
        "src/impl/tcpserver.cpp",
        "src/impl/tcptransport.cpp",
        "src/impl/tlstransport.cpp",
        "src/impl/transport.cpp",
        "src/impl/verifiedtlstransport.cpp",
        "src/impl/websocket.cpp",
        "src/impl/websocketserver.cpp",
        "src/impl/wstransport.cpp",
        "src/impl/wshandshake.cpp",
    ],
    hdrs = glob([
        "include/**/*.h",
        "include/**/*.hpp",
        "src/**/*.h",
        "src/**/*.hpp",
    ], allow_empty = True),
    includes = [
        "include",
        "include/rtc",
        "src",
    ],
    defines = [
        "RTC_ENABLE_MEDIA=1",
        "RTC_ENABLE_WEBSOCKET=0",
        "RTC_STATIC",
        "rtc=bgrtc",
    ],
    local_defines = [
        "RTC_EXPORTS",
        "RTC_SYSTEM_JUICE=0",
        "RTC_SYSTEM_SRTP=0",
        "USE_GNUTLS=0",
        "USE_NICE=0",
    ],
    copts = ["-std=c++17"],
    visibility = ["//visibility:public"],
    deps = [
        ":libjuice",
        ":plog",
        ":usrsctp",
        "//third-party/boringssl:crypto",
        "//third-party/boringssl:ssl",
        "//third-party/webrtc/libsrtp:srtp_public",
    ],
)
