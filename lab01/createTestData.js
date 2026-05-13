const fs = require('fs');
const faker = require('faker');
const { Logging } = require("@google-cloud/logging");

const logName = "pet-theory-logs-createTestData";
const logging = new Logging();
const log = logging.log(logName);
const resource = { type: "global" };

function getRandomCustomerEmail(firstName, lastName) {
  const provider = faker.internet.domainName();
  const email = faker.internet.email(firstName, lastName, provider);
  return email.toLowerCase();
}

async function createTestData(recordCount) {
  const fileName = `customers_${recordCount}.csv`;
  var f = fs.createWriteStream(fileName);
  f.write('id,name,email,phone\n')
  for (let i=0; i<recordCount; i++) {
    const id = faker.datatype.number();
    const firstName = faker.name.firstName();
    const lastName = faker.name.lastName();
    const name = `${firstName} ${lastName}`;
    const email = getRandomCustomerEmail(firstName, lastName);
    const phone = faker.phone.phoneNumber();
    f.write(`${id},${name},${email},${phone}\n`);
  }
  console.log(`Created file ${fileName} containing ${recordCount} records.`);
  const entry = log.entry({ resource: resource }, { message: `Success: createTestData - Created file ${fileName}` });
  log.write([entry]);
}

const recordCount = parseInt(process.argv[2]);
createTestData(recordCount);
