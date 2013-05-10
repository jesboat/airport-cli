//
//  main.m
//  airport-cli
//
//  Created by Jonathan Sailor on 2012-09-11.
//  Copyright (c) 2012 Jonathan Sailor. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <CoreWLAN/CoreWLAN.h>

/* printf, fprintf */
#include <stdio.h>
/* getopt-- it's in unistd, what? */
#include <unistd.h>
/* bzero */
#include <string.h>


static void death(const char *why) {
    fprintf(stderr, "DEATH! %s\n", why);
    exit(1);
}

static void death_nserror(NSError *why) {
    fprintf(stderr, "DEATH!: %s\n", [[why description] UTF8String]);
    exit(1);
}

static void listIfnames() {
    NSSet/*NSString*/ *ifnames = [CWInterface interfaceNames];
    if (ifnames == nil)
        death("[CWInterface interfaceNames] failed");

    for (NSString *ifn in ifnames)
        printf("%s\n", [ifn UTF8String]);
}

static CWInterface *getIf(const char *name_maybe) {
    CWInterface *cwif;

    if (name_maybe && name_maybe[0] != '\0') {
        NSString *ifn = [NSString stringWithUTF8String:name_maybe];
        cwif = [CWInterface interfaceWithName:ifn];
        if (! cwif)
            death("Couldn't get that interface");
    } else {
        cwif = [CWInterface interface];
        if (! cwif)
            death("No AirPort interfaces on this machine?");
    }

    return cwif;
}

static void showIf(CWInterface *cwif) {
    printf("activephymode: %lu\n", [cwif activePHYMode]);
    printf("bssid: %s\n", [[cwif bssid] UTF8String]);
    printf("deviceAttached: %u\n", [cwif deviceAttached] ? 1 : 0);
    printf("hardwareAddress: %s\n", [[cwif hardwareAddress] UTF8String]);
    printf("mode: %lu\n", [cwif interfaceMode]);
    printf("name: %s\n", [[cwif interfaceName] UTF8String]);
    printf("power: %u\n", [cwif powerOn] ? 1 : 0);
    printf("rssi: %ld\n", [cwif rssiValue]);
    printf("security: %lu\n", [cwif security]);
    printf("serviceActive: %u\n", [cwif serviceActive] ? 1 : 0);
    printf("ssid: %s\n", [[cwif ssid] UTF8String]);
}

static void dissoc(CWInterface *cwif) {
    [cwif disassociate];
    // It doesn't give us any way to check for errors :(
}

static const char* band2string(CWChannelBand b) {
    switch (b) {
    case kCWChannelBandUnknown:
        return "unknown";
    case kCWChannelBand2GHz:
        return "2GHz";
    case kCWChannelBand5GHz:
        return "5GHz";
    default:
        return "other";
    }
}

/* <overkill> */

struct enum_poll {
    int v;
    const char *str;
};

const static
struct enum_poll poll_phy_modes[] = {
    {kCWPHYModeNone, "none"},
    {kCWPHYMode11a,  "11a"},
    {kCWPHYMode11b,  "11b"},
    {kCWPHYMode11g,  "11g"},
    {kCWPHYMode11n,  "11n"},
    {0, 0} };

static
BOOL
poll_phy_mode(CWNetwork *net, CWPHYMode m)
{
    return [net supportsPHYMode:m];
}

const static
struct enum_poll poll_security[] = {
    {kCWSecurityNone,                "none"},
    {kCWSecurityWEP,                 "wep"},
    {kCWSecurityWPAPersonal,         "wpa1p"},
    {kCWSecurityWPAPersonalMixed,    "wpa12p"},
    {kCWSecurityWPA2Personal,        "wpa2p"},
    {kCWSecurityPersonal,            "personal"},
    {kCWSecurityDynamicWEP,          "dynamicwep"},
    {kCWSecurityWPAEnterprise,       "wpa1e"},
    {kCWSecurityWPAEnterpriseMixed,  "wpa12e"},
    {kCWSecurityWPA2Enterprise,      "wpa2e"},
    {kCWSecurityEnterprise,          "enterprise"},
    {kCWSecurityUnknown,             "unknown"},
    {0, 0} };

static
BOOL
poll_security_mode(CWNetwork *net, CWSecurity s) {
    return [net supportsSecurity:s];
}

static
const char*
do_enum_poll(const struct enum_poll *polls, CWNetwork *net,
             BOOL (*fn)(CWNetwork*, NSInteger))
{
    static char buf[256];
    int isFirst = 1;

    strcpy(buf, "[");
    for (; polls->str; polls++) {
        if ((*fn)(net, polls->v)) {
            if (! isFirst)
                strcat(buf, ", ");
            strcat(buf, polls->str);
            isFirst = 0;
        }
    }
    strcat(buf, "]");

    return buf;
}

static void scan(CWInterface *cwif, const char *ssidC) {
    NSError *err = nil;

    NSString *ssid = (ssidC ? [NSString stringWithUTF8String:ssidC] : nil);
    NSSet/*CWNetwork*/ *nets = [cwif scanForNetworksWithName:ssid error:&err];

    printf("---\n");
    for (CWNetwork *net in nets) {
        printf("-\n");
        printf(" ssid: %s\n", [net.ssid UTF8String]);
        printf(" bssid: %s\n", [net.bssid UTF8String]);
        printf(" wlanChannel: {number: %ld, band: %s}\n",
               (unsigned long)net.wlanChannel.channelNumber,
               band2string(net.wlanChannel.channelBand));
        printf(" rssi: %ld\n", (long)net.rssiValue);
        printf(" noiseMeasurement: %ld\n", (long)net.noiseMeasurement);
        printf(" countryCode: %s\n", [net.countryCode UTF8String]);
        printf(" beaconInterval: %lu\n", (unsigned long)net.beaconInterval);
        printf(" ibss: %d\n", (net.ibss ? 1 : 0));
        printf(" phys: %s\n", do_enum_poll(poll_phy_modes, net, poll_phy_mode));
        printf(" security: %s\n", do_enum_poll(poll_security, net, poll_security_mode));
    }
}

static void assoc(CWInterface *cwif,
                  const char *ssidC, const char *bssidC,
                  const char *passC)
{
    NSError *err = nil;

    NSString *ssid = [NSString stringWithUTF8String:ssidC];
    NSString *pass = passC ? [NSString stringWithUTF8String:passC] : @"";

    NSSet/*CWNetwork*/ *nets = [cwif scanForNetworksWithName:ssid error:&err];
    if (err)
        death_nserror(err);
    if (! nets)
        death("scanForNetworksWithName returned nil but no error");

    CWNetwork *net = nil;

    if (bssidC) {
        NSString *bssid = [NSString stringWithUTF8String:bssidC];
        for (CWNetwork *n in nets) {
            if ([n.bssid isEqualToString:bssid]) {
                net = n;
                break;
            }
        }
        if (! net)
            death("No networks found with that SSID and BSSID");;
    } else {
        nets = CWMergeNetworks(nets); /* pick strongest signal */
        net = [nets anyObject];
        if (! net)
            death("No networks found with that SSID");
    }

    BOOL ok = [cwif associateToNetwork:net password:pass error:&err];

    if (err)
        death_nserror(err);
    if (ok == NO)
        death("Associate failed, but no error returned");
}

static struct {
    int do_list, do_get, do_assoc, do_dissoc, do_nets;
    const char *ifname;
    const char *ssid, *bssid;
    const char *pass;
    const char *progname;
} glop;

static void usage() {
    fprintf(stderr,
            "Usage: %s [-lgnad] [-i ifname] [-s ssid] [-b bssid] [-p pass]\n"
            "Modes:\n"
            "   -l    list interfaces\n"
            "   -g    get/display interface\n"
            "   -n    list networks\n"
            "   -a    associate\n"
            "   -d    dissociate\n"
            "Options:\n"
            "   -i    interface name; system default if unspecified\n"
            "   -s    SSID (-a, -n only)\n"
            "   -b    BSSID, like 00:00:00:00:00:00 (-a only)\n"
            "   -p    password/key (-a only)\n",
            glop.progname);
    exit(1);
}

static void opts(int argc, char *argv[]) {
    extern char *optarg; /* isn't getopt(3) wonderful? */
    char ch;
    glop.progname = argv[0];
    while ((ch = getopt(argc, argv, "lgnadi:s:b:p:")) != -1) {
        switch (ch) {
            case 'l': glop.do_list=1; break;
            case 'g': glop.do_get=1; break;
            case 'n': glop.do_nets=1; break;
            case 'a': glop.do_assoc=1; break;
            case 'd': glop.do_dissoc=1; break;
            case 'i': glop.ifname=optarg; break;
            case 's': glop.ssid=optarg; break;
            case 'b': glop.bssid=optarg; break;
            case 'p': glop.pass=optarg; break;
            default: usage();
        }
    }
    if (glop.do_list + glop.do_get + glop.do_assoc + glop.do_dissoc + glop.do_nets != 1)
        usage();
    if (glop.do_list) {
        if (glop.ifname || glop.ssid || glop.bssid || glop.pass)
            usage();
    } else if (glop.do_nets) {
        if (glop.bssid || glop.pass)
            usage();
    } else if (glop.do_assoc) {
        if (! glop.ssid)
            usage();
    } else {
        if (glop.ssid || glop.bssid || glop.pass)
            usage();
    }
}

static void app() {
    if (glop.do_list)
        listIfnames();
    else {
        CWInterface *cwif = getIf(glop.ifname);
        if (glop.do_get)
            showIf(cwif);
        else if (glop.do_nets)
            scan(cwif, glop.ssid);
        else if (glop.do_assoc)
            assoc(cwif, glop.ssid, glop.bssid, glop.pass);
        else if (glop.do_dissoc)
            dissoc(cwif);
    }
}

int main(int argc, char * argv[])
{
    @autoreleasepool {
        bzero(&glop, sizeof(glop));
        opts(argc, argv);
        app();
    }
    return 0;
}
