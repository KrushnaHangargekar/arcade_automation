const csv = require('csv-parse');
const fs  = require('fs');
const { Firestore } = require("@google-cloud/firestore");
const { Logging } = require('@google-cloud/logging');

const logName = "pet-theory-logs-importTestData";
const logging = new Logging();
const log = logging.log(logName);
const resource = { type: "global" };

async function writeToFirestore(records) {
  const db = new Firestore();
  const batch = db.batch();
  records.forEach((record) => {
    const docRef = db.collection("customers").doc(record.email);
    batch.set(docRef, record, { merge: true });
  });
  return batch.commit();
}

async function importCsv(csvFilename) {
  const parser = csv.parse({ columns: true, delimiter: ',' }, async function (err, records) {
    if (err) { console.error('Error parsing CSV:', err); return; }
    try {
      await writeToFirestore(records);
      console.log(`Successfully wrote ${records.length} records to Firestore.`);
      const entry = log.entry({ resource: resource }, { message: `Success: importTestData - Wrote ${records.length} records` });
      log.write([entry]);
    } catch (e) { console.error(e); process.exit(1); }
  });
  await fs.createReadStream(csvFilename).pipe(parser);
}

if (process.argv.length < 3) { console.error('Please include a path to a csv file'); process.exit(1); }
importCsv(process.argv[2]).catch(e => console.error(e));
