# scheduler
A scheduler for remote execution of code that is aware of system load and number of users. It attempts to give users on the machine priority by pausing computation if they are logged in and additionally will kill tasks if RAM usage gets too high. Initially developed to use spare linux machines at university.

It keeps itself and the code it is supposed to execute upto date, checks if it has access to the right locations and if is connected to the internet. If any processes hang, crash or get killed an email will be sent to me from the machine with the logs attached. 

As a warning, this likley has a good few bugs in it. I initially wrote to try and understand bash, this whole thing could be rewritten to be much cleaner in python.

Is this a good idea? Probably not, there are much better tools out there for the job
