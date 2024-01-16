const { Sequelize } = require('sequelize');

let connection;
let Balance;

const prepare = async (decimals) => {
  connection = new Sequelize(`postgres://${process.env.POSTGRESQL_CONFIG}/postgres`);
  Balance = require('../models/balance')(connection, decimals);
  try {
    await connection.authenticate();
    console.log('Connection has been established successfully.');
  } catch (error) {
    console.error('Unable to connect to the database:', error);
  }
  await connection.sync();
}

module.exports = async (network, created_at, decimals) => {
  try {
    await prepare(decimals);
    console.log(`There are ${await Balance.count({ where: { network, created_at } })} balances in the network ${network}. Wrapping this up into a variable.`);
    const balances = await Balance.findAll({ 
      attributes: ['amount', 'user_addr'],
      where: { network, created_at }
    });
    await connection.close();
    return balances;
  } finally {
    await connection.close();
  }
}