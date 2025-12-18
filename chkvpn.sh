#!/bin/python3
# -*- codiong: utf-8 -*-
# Ver 0.93
import sys
import os
from selenium.webdriver import Chrome,ChromeOptions
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.common.by import By
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from time import sleep
import sys
import os
import re
import subprocess
import getopt
import datetime
import tempfile
import shutil
gw_ip='192.168.3.8'
up_list='/etc/ppp/ip-up.d/0001vesca'
dn_list='/etc/ppp/ip-down.d/0001vesca'
up_out=['#!/bin/sh\n','systemctl start nftables\n']
dn_out=['#!/bin/sh\n']
servers=[]
Force=False
Skip=False
HeadLess=True
DelAll=False
Verbose=False
CheckOnly=False
EraseOnly=False
def LoginSetting(driver):
	WebDriverWait(driver,5).until(EC.presence_of_all_elements_located)
	pas=driver.find_element(By.NAME,'luci_password')
	pas.clear()
	pas.send_keys('kcbsd-Sayuri')
	login= driver.find_element(By.ID,'loginBtn')
	login.click()
	WebDriverWait(driver,5).until(EC.presence_of_all_elements_located)
	setting=driver.find_element(By.XPATH,'//*[@id="SPAccordionMenuDetails"]/p[2]/a')
	setting.click()
	WebDriverWait(driver,10).until(EC.presence_of_all_elements_located)
def RoutingSetting(driver):
	route= driver.find_element(By.XPATH,'//*[@id="SPAccordionMenuTele"]/ul/li[3]/a')
	route.click()
	WebDriverWait(driver,10).until(EC.presence_of_all_elements_located)
def SaveSetting(driver):
	a=driver.find_element(By.ID,'commit_head')
	a.click()
def GetTableTR(driver):
	tbl=driver.find_element(By.XPATH,'//*[@id="route_tbl"]/table')
	return tbl.find_elements(By.TAG_NAME,'tr')[1:]
def DelRoute(driver,tr):
	id=tr.get_attribute('id')
	a=tr.find_element(By.XPATH,'//*[@id="%s"]/td[4]/p[2]/a'%id)
	a.click()
	WebDriverWait(driver,10).until(EC.alert_is_present())
	alert=driver.switch_to.alert
	alert.accept()
	driver.implicitly_wait( 2 )
	driver.refresh()
def DelRouteAll(driver):
	while True:
		trs=GetTableTR(driver)
		n=len(trs)
		if Verbose:
			print("del cnt:%d"%n,file=sys.stderr)
		if n==0:
			break
		DelRoute(driver,trs[n-1])
	if Verbose:
		print("Delete Done",file=sys.stderr)
	SaveSetting(driver)
	if Verbose:
		print("Saved",file=sys.stderr)
	driver.refresh()
def GetAMG(driver,tr):
	tds=tr.find_elements(By.TAG_NAME,'td')
	s='%s/%s'%(tds[0].text,tds[1].text)
	return s
def ReturnRouteList(driver):
	d=driver.find_element(By.ID,"breadCrum")
	a=d.find_elements(By.TAG_NAME,'a')
	driver.get(a[2].get_attribute('href'))
	driver.implicitly_wait(1)
def SetRoute(driver,amg):
	WebDriverWait(driver,10).until(EC.presence_of_all_elements_located)
	t=amg.split('/')
	inputs=driver.find_elements(By.TAG_NAME,'input')
	inputs[0].clear()
	inputs[1].clear()
	inputs[2].clear()
	inputs[0].send_keys(t[0])
	inputs[1].send_keys(t[1])
	inputs[2].send_keys(t[2])
	a=driver.find_element(By.ID,'iproute_change')
	driver.implicitly_wait( 2 ) 
	a.click()
	WebDriverWait(driver,30).until(EC.alert_is_present())
	alert=driver.switch_to.alert
	alert.accept()
	WebDriverWait(driver,120).until(EC.presence_of_element_located((By.ID, "resultMsg")))
	driver.implicitly_wait( 1 ) 
	p=driver.find_elements(By.CLASS_NAME,"okMessage")
	ReturnRouteList(driver)
	driver.refresh()
	driver.implicitly_wait( 2 ) 
	return True
def EditRoute(driver,tr,amg):
	id=tr.get_attribute('id')
	a=tr.find_element(By.XPATH,'//*[@id="%s"]/td[4]/p[1]/a'%id)
	a.click()
	WebDriverWait(driver,10).until(EC.presence_of_all_elements_located)
	SetRoute(driver,amg)
def AddRoute(driver,amg):
	b=driver.find_element(By.ID,'addBtn')
	b.click()
	SetRoute(driver,amg)
def Logout(driver):
	b=driver.find_element(By.ID,'logout_head')
	b.click()
def AddList(d,s):
	cnt=0
	while cnt<len(d):
		if d[cnt]>s:
			d.insert(0,s)
			break
		cnt+=1
	if cnt==len(d):		
		d.append(s)
def flushRoute(keep,server,adr,gw,old):
	global servers
	ret=0
	if keep and len(adr)>0 and len(old)>0 and server!=None:
		c=len(adr)
		for a in adr:
			if not a in old:
				print("address %s not found in old list:%s"%(a,server),file=sys.stderr)
			else:
				c-=1
		if c>0:
			sys.exit(3)
		servers.append((server,old,gw,None))
		if Verbose:
			print("Server:%s append mode:%s"%(server,"keep"),file=sys.stderr)
	elif not keep and len(adr)>0 and server!=None:
		if old!=adr:
			ret=1
		servers.append((server,adr,gw,old))
		if Verbose:
			print("Server:%s append mode:%s"%(server,"norm" ),file=sys.stderr)
	return ret
def chgList(arg):
	global servers
	ret=0
	server=None
	gw=None
	keep=False
	adr=[]
	old=[]
	t=subprocess.check_output(arg,shell=True).decode().split('\n')
	if Verbose:
		print("arg:%s %d lines"%(arg,len(t)),file=sys.stderr)
	cnt=0
	for s in t:
		cnt+=1
		if s.strip()[0:2] == '##' or s.strip()[0:2] == '# ':
			ret+=flushRoute(keep,server,adr,gw,old)
			keep=True if s.strip()[0:2] == '##' else False
			gw=None
			adr=[]
			old=[]
			server=s[2:].strip()
			n=subprocess.check_output("dig %s"%(server),shell=True).decode().split('\n')
			if Verbose:
				print("dig:%s %d lines"%(server,len(n)),file=sys.stderr)
			for l in n:
				if l[0:1]!=';':
					f=l.split()
					if len(f)==5 and f[3]=='A' and f[2]=='IN' :
						AddList(adr,"%s/32"%f[4])
						if Verbose:
							print("adr:%s append norm"%f[4],file=sys.stderr)
		else:
			r=s.split()
			if len(r)>4 and r[0]=='route' :
				if gw==None:
					gw=r[4]
				AddList(old,"%s/32"%r[2])
				if Verbose:
					print("old:%s append"%r[2],file=sys.stderr)
		if Verbose:
			print("%d processed :%s"%(cnt,s),file=sys.stderr)
	if server!=None and len(adr)>0:
		ret+=flushRoute(keep,server,adr,gw,old)
	return ret
def CheckDuplicate(driver,trs,adrs):
	i=0
	while i<len(adrs):
		j=i+1
		while j<len(trs):
			if GetAMG(driver,trs[j])==adrs[i]:
				return True
			j+=1
		i+=1
	return False
###############################################################################
try:
	opts,args = getopt.getopt( sys.argv[1:], "fsgdcve", ["force","skiproute","gui","delall","erase"] )
except getopt.GetoptError as err:
	print(str(err))
	sys.exit(2)
for o,a in opts:
	match o:
		case "-f" | "--force":
			Force=True
		case "-s" | "--skiproute":
			Skip=True
		case "-g" | "--gui":
			HeadLess=False
		case "-d" | "--delall":
			DelAll=True
		case "-c" | "--check":
			CheckOnly=True
		case "-v" | "--verbose":
			Verbose=True
		case "-e" | "--erase":
			EraseOnly=True
chg=chgList('ssh root@%s cat %s'%(gw_ip,up_list))
if not Force and not EraseOnly and chg==0:
	print("Same Setting",file=sys.stderr)
	sys.exit(0)
if CheckOnly:
	print("%s differ Setting"%chg,file=sys.stderr)
	for s,aa,g,oo in servers:
		sd=0
		if oo!=None and aa!=oo:
			if sd==0:
				print("server:%s"%s,file=sys.stderr)
				sd=1
			for a in aa:
				if not a in oo:
					print(" new:%s"%a,file=sys.stderr)
			for o in oo:
				if not o in aa:
					print(" del:%s"%o,file=sys.stderr)
	sys.exit(1)
dir=tempfile.mkdtemp()
fu=open("%s/up.d"%dir,mode='w')
fd=open("%s/dn.d"%dir,mode='w')
d=[]
u=[]
adrs=[]
for s,aa,g,o in servers:
	if o==None:
		d.append('##%s\n'%s)
		u.append('##%s\n'%s)
	else:
		d.append('# %s\n'%s)
		u.append('# %s\n'%s)
	for a in aa:
		adrs.append("%s/%s"%(a,gw_ip))
		u.append('route add %s gw %s\n'%(a.split('/')[0],g))
		d.append('route del %s gw %s\n'%(a.split('/')[0],g))
if Verbose:
	print("adrs:%d address reading tempdir:%s"%(len(adrs),dir))
adrs.append('192.168.2.0/24/192.168.3.5')
up_out.extend(u)
dn_out.extend(d)
up_out.append('exit 0\n')
dn_out.append('systemctl stop nftables\n')
dn_out.append('exit 0\n')

fu.writelines(up_out)
fd.writelines(dn_out)
fu.close()
fd.close()
subprocess.run(["scp", 'root@%s:%s'%(gw_ip,up_list),'%s.bak'%os.path.basename(up_list)])
subprocess.run(["scp",'%s/up.d'%dir,'root@%s:%s'%(gw_ip,up_list)])
subprocess.run(["ssh",'root@%s'%gw_ip,'systemctl','restart','xl2tpd'])
subprocess.run(["scp",'%s/dn.d'%dir,'root@%s:%s'%(gw_ip,dn_list)])
shutil.rmtree(dir)
if Skip:
	sys.exit(0)
print("Total:%d"%len(adrs),file=sys.stderr)
options= ChromeOptions()
if HeadLess:
	options.add_argument('--headless')
	options.add_argument('--window-size=1920,1080')
if os.environ['OSTYPE']=='FreeBSD':
	drv_path='/usr/local/bin/chromedriver'
	options.binary_location='/usr/local/bin/chrome'
else:
	drv_path='/usr/bin/chromedriver'
driver= Chrome(service=Service(drv_path),options=options)
driver.get('http://192.168.3.1/cgi-bin/gui/default/system')
LoginSetting(driver)
RoutingSetting(driver)
lenAdrs=len(adrs)
trs= GetTableTR(driver)
if len(trs)>lenAdrs or CheckDuplicate(driver,trs,adrs):
	DelAll=True
if not DelAll and not EraseOnly:
	src=0
	dst=0
	while not DelAll and src<lenAdrs:
		if dst<len(trs):
			driver.implicitly_wait( 2 )
			chg=0
			while GetAMG(driver,trs[dst])!=adrs[src]:
				chg=1
				if Verbose:
					print("%d,%d:%s!=%s"%(dst,src,GetAMG(driver,trs[dst]),adrs[src]),file=sys.stderr)
				EditRoute(driver,trs[dst],adrs[src])
				WebDriverWait(driver,5).until(EC.presence_of_all_elements_located)
				trs= GetTableTR(driver)
			if Verbose and chg==0:
				print("%d,%d:%s==%s"%(dst,src,GetAMG(driver,trs[dst]),adrs[src]),file=sys.stderr)
			src+=1
		else:
			while len(trs)<dst:
				AddRoute(driver,adrs[src])
				WebDriverWait(driver,5).until(EC.presence_of_all_elements_located)
				trs= GetTableTR(driver)
		dst+=1
if DelAll or EraseOnly:
	DelRouteAll(driver)
	if EraseOnly:
		b=driver.find_element(By.ID,'logout_head')
		b.click()
		driver.quit()
		sys.exit(0)
	# WebDriverWait(driver,120).until(EC.presence_of_all_elements_located)
	cnt=0
	for a in adrs:
		cnt+=1
		print("addr:%s cnt:%d"%(a,cnt),file=sys.stderr)
		while True:
			AddRoute(driver,a)
			WebDriverWait(driver,5).until(EC.presence_of_all_elements_located)
			trs= GetTableTR(driver)
			n=len(trs)
			print("add trs:%d"%n,file=sys.stderr)
			if n==cnt:
				break
SaveSetting(driver)
Logout(driver)
driver.quit()
sys.exit(0)
