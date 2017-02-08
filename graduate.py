#!/usr/bin/env python
# -*- coding: utf-8 -*-

import json

components = ['processor', 'RAM']
params = ['CPU', 'frequency', 'L3', 'bogoMIPS', 'total', 'vendor', 'model']
PROC = ['i3', 'i5', 'i7', 'Xeon']
NET = ['e1000', 'ixgbe', 'xgbe', 'gbe']
VM = ['QEMU','VirtualBox','VMVARE', 'KVM']
graduate = dict()

with open('/tmp/data.json') as data_file:
    data = json.load(data_file)

def grade_num(system, param, MIN, MAX, scale=10):
    """Генерация оценки из полученных параметров"""
    try:
        current_value = data[system][param]
        if current_value == '':
            return 1
        elif current_value.isalnum():
            current_value = float(''.join([i if i.isdigit() else '' for i in current_value]))
        else:
            current_value = float(current_value)
        if current_value < MIN:
            return 1
        elif current_value >= MAX:
            return 10
        raiting = dict(i for i in enumerate(range(MIN,MAX,int((MAX-MIN)/scale)),1))
        return next((i for i, v in raiting.items() if v > current_value), None)
    except KeyError:
        return 'Invalid parameter key'

def grade_string(system, param,good_value):
    try:
        current_value = data[system][param]
        return max([10 if i in current_value else 1 for i in good_value])
    except KeyError:
        return 'Invalid parameter key'

def grade_iface(system, param,key, good_value):
    try:
        current_value = data[system][param][key]
        return max([10 if i in current_value else 1 for i in good_value])
    except KeyError:
        return 'Invalid parameter key'

def results():
    graduate.update({params[0]:grade_num(components[0],params[0], 1, 12, 11)})
    graduate.update({params[1]:grade_num(components[0],params[1], 2*1000, 4*1000)})
    graduate.update({params[2]:grade_num(components[0],params[2], 4*1000, 8*1000)})
    graduate.update({params[3]:grade_num(components[0],params[3], 4*1000, 10*1000)})
    graduate.update({params[4]:grade_num(components[1],params[4], 400*1000, 12*1000*1000)})
    graduate.update({params[5]:grade_string(components[0],params[5], 'GenuineIntel')})
    graduate.update({params[6]:grade_string(components[0],params[6], PROC)})
    for iface in data['interfaces'].keys():
        graduate.update({"driver %s" % iface:grade_iface('interfaces', iface, 'driver', NET)})
        graduate.update({"queue_count %s" % iface:grade_iface('interfaces', iface, 'queue_count', '4')})
    graduate.update({'HDD': not grade_string('HDD','model', VM)})
    print(float(sum(graduate.values())) / len(graduate))

if __name__ == "__main__":
    results()
