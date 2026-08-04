FROM python:3.13-slim

RUN pip install --no-cache-dir ansible ansible-lint yamllint pynetbox \
    && ansible-galaxy collection install cisco.ios netbox.netbox

ENV ANSIBLE_INVENTORY_ENABLED=netbox.netbox.nb_inventory,auto,yaml,ini

WORKDIR /workspace
