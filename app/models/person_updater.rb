class PersonUpdater
  def self.update_people_from_ps
    pu = PersonUpdater.new # Even though this could be a fully static class, I think it's more readable to deal with variables within an instance
    pu.update_people
  end
  
  def update_people
    update_staff_records
#    update_person_records
  end
  
  private
  
  def update_staff_records
    insert_and_remove_staff_records
    update_staff_record_attributes
  end
  
  def insert_and_remove_staff_records
    staff = Staff.select("accountNo").where("removedFromPeopleSoft = 'N'").all.collect(&:accountNo)
    pstaff = PsEmployee.select("emplid, first_name, last_name").order("emplid")
    pstaff.each do |p_record|
      s_record = Staff.find_by_accountNo(p_record.emplid)
      if s_record # This record exists already
        # Check to make sure it's the right person
        if s_record.lastName.upcase == p_record.last_name.upcase && s_record.firstName.upcase == p_record.first_name.upcase
          staff.delete(p_record.emplid)
          Rails.logger.info("Record #{p_record.emplid} exists (#{p_record.first_name.to_s + " " + p_record.last_name.to_s}).")
        else # Name doesn't match
          maiden = PsCccPersData.where("emplid = ?", p_record.emplid).first
          if maiden && !maiden.maiden_emplid.blank? # Changed emplid at some point
            maiden_record = Staff.find_by_accountNo(maiden.maiden_emplid)
            # Check maiden record for name accuracy
            if maiden_record && maiden_record.lastName.upcase == p_record.last_name.upcase && maiden_record.firstName.upcase == p_record.first_name.upcase
              # Name is correct in maiden_record
              unless Staff.find_by_accountNo(s_record.accountNo + "_old")
                s_record.update_attribute(:accountNo, s_record.accountNo + "_old")
                s_record.removedFromPeopleSoft = "Y"
                s_record.person_id = nil
                s_record.save!
              else # There's already an _old record, so we'll just get rid of this one
                s_record.destroy
              end
              switch_account_number(maiden_record, p_record.emplid)
              staff.delete(p_record.emplid)
              Rails.logger.info("Record #{p_record.emplid} existed (#{p_record.first_name.to_s + " " + p_record.last_name.to_s}), but name didn't match (#{s_record.firstName.to_s + " " + s_record.lastName.to_s}).  Found maiden record #{maiden.maiden_emplid} and switched account numbers.")
            elsif maiden_record
              # Name is incorrect in maiden_record, will switch anyway
              unless Staff.find_by_accountNo(s_record.accountNo + "_old")
                s_record.update_attribute(:accountNo, s_record.accountNo + "_old")
                s_record.removedFromPeopleSoft = "Y"
                s_record.person_id = nil
                s_record.save!
              else # There's already an _old record, so we'll just get rid of this one
                s_record.destroy
              end
              switch_account_number(maiden_record, p_record.emplid)
              staff.delete(p_record.emplid)
              Rails.logger.info("Record #{p_record.emplid} existed (#{p_record.first_name.to_s + " " + p_record.last_name.to_s}), but name didn't match (#{s_record.firstName.to_s + " " + s_record.lastName.to_s}).  Found maiden record #{maiden.maiden_emplid} but name still didn't match (#{maiden_record.firstName.to_s + " " + maiden_record.lastName.to_s}).  Switched account numbers anyway.")
            else
              # Maiden record not found in our database, leave as is.
              staff.delete(p_record.emplid)
              Rails.logger.info("Record #{p_record.emplid} exists (#{p_record.first_name.to_s + " " + p_record.last_name.to_s}), but name doesn't match (#{s_record.firstName.to_s + " " + s_record.lastName.to_s}).  Maiden record exists in PS, not in Staff table.  Leaving as is.")
            end
          else
            staff.delete(p_record.emplid)
            Rails.logger.info("Record #{p_record.emplid} exists (#{p_record.first_name.to_s + " " + p_record.last_name.to_s}), but name doesn't match (#{s_record.firstName.to_s + " " + s_record.lastName.to_s}).  No maiden record found.  Leaving as is.")
          end
        end
      else # record does not exist
        maiden = PsCccPersData.where("emplid = ?", p_record.emplid).first
        if maiden && !maiden.maiden_emplid.blank? # Changed emplid at some point
          s_record = Staff.find_by_accountNo(maiden.maiden_emplid)
          if s_record
            switch_account_number(s_record, maiden.emplid)
            staff.delete(maiden.maiden_emplid)
            Rails.logger.info("Record #{p_record.emplid} did not exist (#{p_record.first_name.to_s + " " + p_record.last_name.to_s}).  Found old record #{maiden.maiden_emplid} from maiden table and switched account numbers for staff record (#{s_record.firstName.to_s + " " + s_record.lastName.to_s}).")
          else
            s = Staff.new({:firstName => p_record.first_name, :lastName => p_record.last_name, :removedFromPeopleSoft => "N"})
            s.accountNo = p_record.emplid
            s.save!
            Rails.logger.info("Record #{p_record.emplid} did not exist (#{p_record.first_name.to_s + " " + p_record.last_name.to_s}).  Did not find a record from maiden table.  Created new record.")
          end
        else
          s = Staff.new({:firstName => p_record.first_name, :lastName => p_record.last_name, :removedFromPeopleSoft => "N"})
          s.accountNo = p_record.emplid
          s.save!
          Rails.logger.info("Record #{p_record.emplid} did not exist (#{p_record.first_name.to_s + " " + p_record.last_name.to_s}).  Did not find a record in maiden table.  Created new record.")
        end
      end
    end
    
    # Staff records not accounted for in PS, check and set removedFromPeopleSoft to "Y"
    staff.each do |account_no|
      s_record = Staff.find_by_accountNo(account_no)
      if s_record
        if PsEmployee.find_by_emplid(s_record.accountNo)
          Rails.logger.info("Record #{s_record.accountNo} is in PS but was never checked off.  Why????????????????????????")
        else
          s_record.removedFromPeopleSoft = "Y"
          s_record.save!
          Rails.logger.info("Record #{s_record.accountNo} removed from PS.")
        end
      end
    end
  end
  
  def update_staff_record_attributes
    ps_records = PsEmployee.includes(:psTaxLocation).order(:emplid)
    ps_records.each do |ps_record|
      staff = Staff.find_by_accountNo(ps_record.emplid)
      if staff
        set_staff_attributes(staff, ps_record)
        staff.save!
      else
        Rails.logger.info("Could not find Record #{ps_record.emplid} (#{ps_record.first_name.to_s + " " + ps_record.last_name.to_s} in Staff table while performing attributes update.)")
      end
    end
  end
  
  def switch_account_number(staff, account_no)
    old_record = staff.dup
    staff.removedFromPeopleSoft = "N"
    staff.accountNo = account_no
    staff.save!
    old_record.removedFromPeopleSoft = "Y"
    old_record.person_id = nil
    old_record.save!
  end
  
  def set_staff_attributes(staff, ps_record)
    staff.isMale = ("M" == ps_record.sex)
    staff.birthDate = ps_record.birthdate
    staff.maritalStatus = ps_record.mar_status
    staff.marriageDate = ps_record.mar_status_dt
    if "E" == ps_record.employee_flag
      staff.hireDate = ps_record.hire_dt
      staff.rehireDate = ps_record.rehire_dt
      staff.origHiredate = ps_record.orig_hire_dt
    else
      staff.hireDate = nil
      staff.rehireDate = nil
      staff.origHiredate = nil
    end
    staff.serviceDate = ps_record.service_dt
    staff.workPhone = ps_record.work_phone
    staff.deptId = ps_record.deptid
    staff.jobCode = ps_record.jobcode
    staff.accountCode = ps_record.acct_cd
    staff.jobTitle = ps_record.jobtitle
    staff.deptName = ps_record.deptname
    
    staff.primaryEmpLocCity = ps_record.psTaxLocation.city
    staff.primaryEmpLocState = ps_record.psTaxLocation.state
    staff.primaryEmpLocCountry = ps_record.psTaxLocation.country
    staff.primaryEmpLocDesc = ps_record.psTaxLocation.descr
    
    staff.jobStatus = PsCccStatusTbl.translate_status(ps_record.status_code)
    staff.ministry = PsDeptTbl.translate_ministry(ps_record.ccc_ministry)
    staff.region = PsRegion.translate_region(ps_record.ccc_sub_ministry)
    staff.strategy = PsStrategy.translate_strategy(ps_record.lane_outreach)
    staff.position = PsRespScope.translate_resp_scope(ps_record.respons_scope)

    staff.middleName = ps_record.middle_name
    staff.statusDescr = ps_record.status_descr
    staff.internationalStatus = ps_record.internation_status
    staff.balance = ps_record.balance
    staff.cccHrSendingDept = ps_record.ccc_hr_sndng_dept
    staff.cccHrCaringDept = ps_record.ccc_hr_caring_dept
    staff.cccCaringMinistry = ps_record.ccc_carng_ministry
    staff.assignmentLength = ps_record.assignment_lngth
    

    # guarentees that if a staff is reloaded at night, they are said to be on peoplesoft.  (I.E., seen on Infobase)
    staff.removedFromPeopleSoft = "N"

    # Update spousal info
    update_spouse_info(staff, ps_record)

    staff.reportingDate = ps_record.reporting_date
    staff.coupleTitle = ps_record.couple_name_prefix
    staff.firstName = ps_record.first_name
    staff.lastName = ps_record.last_name
    staff.email = ps_record.email_addr.strip
    staff.preferredName = ps_record.pref_first_name
    staff.homePhone = ps_record.home_phone
    staff.otherPhone = ps_record.phone # Actually a duplicate of home phone
    staff.mobilePhone = ps_record.cell_phone

    staff.countryCode = ps_record.nid_country

    if "SECURE" != staff.countryCode.upcase 
      setAddr(staff, ps_record)
    end
    
    staff.isSecure = ps_record.secure_employee == "Y"
    
    Rails.logger.info("Changes for #{ps_record.emplid} (#{ps_record.first_name.to_s + " " + ps_record.last_name.to_s}):  #{staff.changes}")
  end
  
  def update_spouse_info(staff, ps_record)
    staff.spouseFirstName = ps_record.spouse_name
    staff.spouseLastName = ps_record.last_name
    
    accountNo = ps_record.emplid
    
    # If husband account
    if accountNo.size == 9 && accountNo.last != 'S'
      wife_account_no = accountNo + "S";
      wife = Staff.find_by_accountNo(wife_account_no)
      if wife
        staff.spouseAccountNo = wife_account_no      
        wife.spouseAccountNo = accountNo
        wife.save!
      end
    elsif accountNo.size == 10 && accountNo.last == 'S'
      husband_account_no = accountNo.substring(0,9)
      husband = Staff.find_by_accountNo(husband_account_no)
      if husband
        staff.spouseAccountNo = husband_account_no     
        husband.spouseAccountNo = accountNo
        husband.save!
      end
    end
  end
  
  def set_addr(staff, ps_record)
    add1 = staff.primary_address
    unless add1
      add1 = StaffAddress.new
      Rails.logger.info("Address1 for " + staff.firstName + " " + staff.lastName + " not persistant; creating new one");
    end
    add1.address1 = ps_record.address1
    add1.address2 = ps_record.address2
    add1.address3 = ps_record.address3
    add1.address4 = ps_record.address4
    add1.city = ps_record.city
    add1.state = ps_record.state
    add1.zip = ps_record.postal
    add1.country = ps_record.country
    add1.save!
    staff.primary_address = add1
    
    add2 = staff.secondary_address
    unless add2
      add2 = StaffAddress.new
      Rails.logger.info("Address2 for " + staff.firstName + " " + staff.lastName + " not persistant; creating new one");
    end
    add2.address1 = ps_record.address1_other
    add2.address2 = ps_record.address2_other
    add2.address3 = ps_record.address3_other
    add2.city = ps_record.city_other
    add2.state = ps_record.state_other
    add2.zip = ps_record.postal_other
    add2.country = ps_record.country_other
    add2.save!
    staff.secondary_address = add2
  end
end