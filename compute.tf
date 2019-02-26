### To Provision FireWall rule ###

resource "google_compute_firewall" "www" {
  name = "tf-www-firewall"
  network = "default"

  allow {
    protocol = "tcp"
    ports = ["8081", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
}

### To provision Nexus ###

resource "google_compute_instance" "nexus-1" {
  name = "nexus-master-1"
  machine_type = "n1-standard-1"
  zone = "asia-southeast1-b"
  tags = ["nexus"]
  boot_disk {
    initialize_params {
      image = "ubuntu-1604-lts"
    }
  }
  network_interface {
    network = "default"
    access_config {}
  }
  service_account {
    scopes = ["userinfo-email", "compute-ro", "storage-ro","cloud-platform"]
  }

  metadata{
    startup-script = <<SCRIPT
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
sudo apt-get update
apt-cache policy docker-ce
sudo apt-get install -y docker-ce
sudo apt-get install -y maven
sudo mkdir /opt/nexus
cd /opt/nexus && git clone https://github.com/sonatype-nexus-community/nexus-blobstore-google-cloud.git
cd /opt/nexus/nexus-blobstore-google-cloud && sudo mvn clean package
wait
cd /opt/nexus/nexus-blobstore-google-cloud
sudo echo "FROM sonatype/nexus3:3.14.0
ADD install-plugin.sh /opt/plugins/nexus-blobstore-google-cloud/
COPY /target/ /opt/plugins/nexus-blobstore-google-cloud/target/
COPY pom.xml /opt/plugins/nexus-blobstore-google-cloud/

USER root

RUN cd /opt/plugins/nexus-blobstore-google-cloud/ && \
    chmod +x install-plugin.sh && \
        ./install-plugin.sh /opt/sonatype/nexus/ && \
	    rm -rf /opt/plugins/nexus-blobstore-google-cloud/

RUN chown -R nexus:nexus /opt/sonatype/

USER nexus
" > /opt/nexus/nexus-blobstore-google-cloud/Dockerfile
wait
sudo docker build -t sonatype/customnexus .
wait
sudo docker run -d -p 8081:8081 --name nexus sonatype/customnexus
docker run -d -p 5000:5000 --restart=always --name registry registry:2
docker tag sonatype/customnexus localhost:5000/sonatype/customnexus
docker push localhost:5000/sonatype/customnexus

export CLOUD_SDK_REPO="cloud-sdk-$(lsb_release -c -s)"

echo "deb http://packages.cloud.google.com/apt $CLOUD_SDK_REPO main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list

curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -

sudo apt-get update && sudo apt-get install google-cloud-sdk

cd /home

sudo echo "
{
  "type": "service_account",
  "project_id": "wlsiowproject-220315",
  "private_key_id": "removed",
  "private_key": "removed"
  "client_email": "k8-525@wlsiowproject-220315.iam.gserviceaccount.com",
  "client_id": "100192794237809042089",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token",
  "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
  "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/k8-525%40wlsiowproject-220315.iam.gserviceaccount.com"
}
" > key.json

sudo apt-get update && sudo apt-get install -y apt-transport-https
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee -a /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubectl

sudo gcloud auth activate-service-account --key-file key.json
sudo gcloud container clusters get-credentials your-first-cluster-1 --zone asia-southeast1-b

sudo echo "
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: nexus
  namespace: stg
spec:
  replicas: 1
  template:
    metadata:
      labels:
        app: nexus-server
    spec:
      containers:
        - name: nexus
          image: 10.148.0.17:5000/sonatype/customnexus
          resources:
            limits:
              memory: "2Gi"
              cpu: "500m"
            requests:
              memory: "1Gi"
              cpu: "250m"
          ports:
            - containerPort: 8081
          volumeMounts:
            - name: nexus-data
              mountPath: /nexus-data
      volumes:
        - name: nexus-data
          emptyDir: {}
" > deployment.yaml

sudo kubectl create -f deployment.yaml

sudo echo "
apiVersion: v1
kind: Service
metadata:
  labels:
    app: nexus-server
  name: nexus
  namespace: stg
spec:
  ports:
  - port: 80
    protocol: TCP
    targetPort: 8081
  selector:
    app: nexus-server
  sessionAffinity: None
  type: ClusterIP
" > deployment-service.yaml

sudo kubectl create -f deployment-service.yaml

SCRIPT

    sshKeys = "ubuntu:${file("~/.ssh/id_rsa.pub")}"
  }


}
