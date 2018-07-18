// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright © 2016-2018 ANSSI. All Rights Reserved.
#define _GNU_SOURCE
#include<stdlib.h>
#include<unistd.h>
int main()
{
  char *myargv[5]={"/usr/bin/lxc-stop","-n","sdk-mirror","-k",0};
  setresuid(0,0,0); 
//  myargv[2]=argv[1];
  execve("/usr/bin/lxc-stop",myargv, NULL);
}
