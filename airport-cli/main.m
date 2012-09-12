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

static void assoc(CWInterface *cwif, const char *ssidC, const char *passC) {
    NSError *err = nil;

    NSString *ssid = [NSString stringWithUTF8String:ssidC];
    NSString *pass = passC ? [NSString stringWithUTF8String:passC] : @"";

    NSSet/*CWNetwork*/ *nets = [cwif scanForNetworksWithName:ssid error:&err];
    if (err)
        death_nserror(err);
    if (! nets)
        death("scanForNetworksWithName returned nil but no error");

    nets = CWMergeNetworks(nets); /* pick strongest signal */

    CWNetwork *net = [nets anyObject]; /* nil if nets is empty */
    if (! net)
        death("No networks found with that SSID");

    BOOL ok = [cwif associateToNetwork:net password:pass error:&err];

    if (err)
        death_nserror(err);
    if (ok == NO)
        death("Associate failed, but no error returned");
}

static struct {
    int do_list, do_get, do_assoc, do_dissoc;
    const char *ifname;
    const char *ssid;
    const char *pass;
    const char *progname;
} glop;

static void usage() {
    fprintf(stderr,
            "Usage: %s [-lgpad] [-i ifname] [-s ssid] [-p pass]\n"
            "Modes:\n"
            "   -l    list interfaces\n"
            "   -g    get/display interface\n"
            "   -a    associate\n"
            "   -d    dissociate\n"
            "Options:\n"
            "   -i    interface name; system default if unspecified\n"
            "   -s    SSID (-a only)\n"
            "   -p    password/key (-a only)\n",
            glop.progname);
    exit(1);
}

static void opts(int argc, char *argv[]) {
    extern char *optarg; /* isn't getopt(3) wonderful? */
    char ch;
    glop.progname = argv[0];
    while ((ch = getopt(argc, argv, "lgadi:s:p:")) != -1) {
        switch (ch) {
            case 'l': glop.do_list=1; break;
            case 'g': glop.do_get=1; break;
            case 'a': glop.do_assoc=1; break;
            case 'd': glop.do_dissoc=1; break;
            case 'i': glop.ifname=optarg; break;
            case 's': glop.ssid=optarg; break;
            case 'p': glop.pass=optarg; break;
            default: usage();
        }
    }
    if (glop.do_list + glop.do_get + glop.do_assoc + glop.do_dissoc != 1)
        usage();
    if (glop.do_list) {
        if (glop.ifname || glop.ssid || glop.pass)
            usage();
    } else if (glop.do_assoc) {
        if (! glop.ssid)
            usage();
    } else {
        if (glop.ssid || glop.pass)
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
        else if (glop.do_assoc)
            assoc(cwif, glop.ssid, glop.pass);
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
