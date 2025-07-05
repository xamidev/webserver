# webserver

Written as a tiny project to learn more about 64-bit x86 assembly and the Linux kernel ABI. The syntax here is Intel for GNU AS. The code is public domain.

### Build process

```
as -g server.s -o server.o && ld server.o -o exe
sudo ./exe 
```

### Testing

```
nc localhost 80
GET /anything HTTP/1.0
POST /anything HTTP/1.0
```

### Warning

The executable needs root permissions because it is listening for incoming connections everywhere (0.0.0.0).
Therefore, if your server is running on the default address, anyone on the network can access and/or create any file on your machine.
 
Change the `sockaddr_in` struct in the data section to override this.
