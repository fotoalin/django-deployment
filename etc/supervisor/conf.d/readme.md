# Notes

## Daphne

notes from https://github.com/django/daphne

>_If daphne is being run inside a process manager, you might want it to bind to a file descriptor passed down from a parent process. To achieve this you can use the `--fd` flag_
>
>`daphne --fd 5 django_project.asgi:application`

I believe this doesn't apply to supervisor as it automatically handles the file descriptor.

> I have trid to run daphne with -e ssl:445 and it didn't work
> `daphne -e ssl:443:privateKey=key.pem:certKey=crt.pem django_project.asgi:application`
