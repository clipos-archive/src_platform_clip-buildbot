// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright © 2016-2018 ANSSI. All Rights Reserved.
#define _GNU_SOURCE
#include<stdlib.h>
#include<unistd.h>
int main()
{
  char *myargv[7]={"/usr/bin/lxc-start-ephemeral","--lxcpath","/var/lib/lxc","-o","sdk-test","-d",0};
  setresuid(0,0,0);
  execve("/usr/bin/lxc-start-ephemeral",myargv, NULL);
}
