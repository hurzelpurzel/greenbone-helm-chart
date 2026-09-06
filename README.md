# greenbone-helm-chart

The OpenVAS and Greenbone Community Edition is a great tool for 
Vulnerabiltiy Assesment.


Currently there is a onl a docker-compose variant. This helmchart took the docker-compose file from
https://greenbone.github.io/docs/latest/22.4/container/#docker-compose-file , translate it to k8s using kompose and create a helm Chart from the results.

Goal is making it easier to consume from Kubernetes


## Create Image Pull Secret

You can create an account through the Greenbone Community Portal:

 Go to https://community.greenbone.net
    Select Register or Sign up.
    Confirm your email address.
 
 Use those credentials to authenticate to registry.community.greenbone.net.
